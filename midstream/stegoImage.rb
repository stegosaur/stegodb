#!/usr/bin/env ruby
require 'json'
require 'yaml'
require 'sequel'
require 'logger'
require 'mini_magick'

class Image
  def b2auth(account_id=$config["b2account"],application_key=$config["b2key"],bucket_id=$config["b2bucket"])
    uri = URI("https://api.backblazeb2.com/b2api/v2/b2_authorize_account")
    req = Net::HTTP::Get.new(uri)
    req.basic_auth(account_id, application_key)
    http = Net::HTTP.new(req.uri.host, req.uri.port)
    http.use_ssl = true
    res = http.start {|http| http.request(req)}
    case res
    when Net::HTTPSuccess then
        tokenjson = res.body
    when Net::HTTPRedirection then
        fetch(res['location'], limit - 1)
    else
        res.error!
    end
    b2auth = JSON.parse(tokenjson)
    b2auth["expire"] = (Time.now + 3600*24).to_s
    uri = URI("#{b2auth["apiUrl"]}/b2api/v2/b2_get_upload_url")
    req = Net::HTTP::Post.new(uri)
    req.add_field("Authorization",b2auth["authorizationToken"])
    req.body = "{\"bucketId\":\"#{bucket_id}\"}"
    http = Net::HTTP.new(req.uri.host, req.uri.port)
    http.use_ssl = true
    res = http.start {|http| http.request(req)}
    case res
    when Net::HTTPSuccess then
      urljson=res.body
    when Net::HTTPRedirection then
      fetch(res['location'], limit - 1)
    else
      res.error!
    end
    urljson=JSON.parse(urljson)
    urljson["uploadToken"] = urljson.delete("authorizationToken")
    b2auth.merge!(urljson)
    File.write('/tmp/b2auth.txt', b2auth.to_json)
    @@b2auth = b2auth.dup
    return b2auth
  end

  def b2upload(data,thumb,sign)
    t0=Time.now
    unless Image.class_variable_defined?(:@@b2auth)
      if File.exists?('/tmp/b2auth.txt')
        @@b2auth = JSON.parse(File.read('/tmp/b2auth.txt'))
        if Time.parse(@@b2auth["expire"]) > Time.now
          logger.info("no valid token found, generating new B2 auth token")
          b2auth()
        end
      else
        logger.info("no valid token found, generating new B2 auth token")
        b2auth()
      end
    end
    filename=sign[0,3] + "/" + sign
    filename=sign[0,3] + "/thumb/" + sign if thumb
    filename=filename+".jpg"
    uri = URI(@@b2auth["uploadUrl"])
    req = Net::HTTP::Post.new(uri)
    req.add_field("Authorization",@@b2auth["uploadToken"])
    req.add_field("X-Bz-File-Name",filename)
    req.add_field("Content-Type","image/jpeg")
    req.add_field("X-Bz-Content-Sha1",Digest::SHA1.hexdigest(data))
    req.add_field("Content-Length",data.size)
    req.body = data
    http = Net::HTTP.new(req.uri.host, req.uri.port)
    http.use_ssl = (req.uri.scheme == 'https')
    begin
      tries ||=0
      res = http.start {|http| http.request(req)}
      case res
      when Net::HTTPSuccess then
        response=JSON.parse(res.body)
      when Net::HTTPRedirection then
        fetch(res['location'], limit - 1)
      else
        if (0..9).cover?(tries)
          logger.error("B2 upload failed for item with signature #{sign}, retrying (#{tries})...")
          raise
        elsif (10..12).cover?(tries)
          sleep 1
          b2auth()
          logger.error("retrying B2 upload with new credentials (#{tries})...")
          raise
        end
      end
    rescue Exception => e
      if (tries += 1) < 13
        retry
      else
        raise 'b2fail'
      end
    end
    response["signature"] = sign
    t1=Time.now
    uptime=t1-t0.round(3)
    ppsize=data.size.to_s.chars.to_a.reverse.each_slice(3).map(&:join).join(",").reverse
    logger.info("#{ppsize} bytes pushed to B2 in #{uptime} seconds (#{(data.size/uptime/1024).round(2)}k/sec)")
    return response
  end

  def aspectPad(image)
    path=image.path
    MiniMagick::Tool::Convert.new do |cmd|
      cmd << path
      cmd << "-fuzz"
      cmd << "7%"
      cmd << "-trim"
      cmd << path
    end
    image=MiniMagick::Image.open(path)
    scale1=(4.0/3) / image.dimensions[0] * image.dimensions[1]
    scale2=1/scale1
    MiniMagick::Tool::Convert.new do |cmd|
      cmd << path
      cmd << "-gravity"
      cmd << "center"
      cmd << "-extent"
      cmd << "#{(image.dimensions[0]*(scale1)).floor}x#{image.dimensions[1]}" if scale1 >= 1
      cmd << "#{image.dimensions[0]}x#{(image.dimensions[1]*(scale2)).floor}" unless scale1 >= 1
      cmd << path
    end
    image=MiniMagick::Image.open(path)
    return image
  end

  def getImage(url)
    return MiniMagick::Image.open(url)
  end
end
