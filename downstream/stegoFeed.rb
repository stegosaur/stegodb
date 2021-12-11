#!/usr/bin/env ruby
$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__))) unless $LOAD_PATH.include?(File.expand_path(File.dirname(__FILE__)))
require 'pp'
require 'csv'
require 'json'
require 'yaml'
require 'net/ftp'
require 'logger'
require 'zlib'
require 'stegoDB'
$config=YAML.load_file("#{$LOAD_PATH[0]}/config.yml")

class Feeder
  def impactFTP(ftpHost=$config['ftpHost'],ftpUser=$config['ftpUser'],ftpPass=$config['ftpPass'],logpath=STDOUT)
    logger=Logger.new(logpath)
    ftp=Net::FTP.open(ftpHost)
    ftp.read_timeout=300
    ftp.login(ftpUser,ftpPass)
    files = ftp.chdir("/Walmart-Affiliate-Program/")
    files = ftp.list('*CUSTOM*').map{|f| f.split(" ")[-1]}
    files.each{|file|
      t0=Time.now
      transferred=0
      outfile="walmart/#{Time.now.to_i}.#{file}"
      ftp.getbinaryfile(file, outfile, 1024*1) { |data|
        transferred += data.size
        logger.info("downloading #{outfile} #{(transferred/1024.0/1024.0).round(4)}mb (#{(transferred/(Time.now-t0)/1024).round(2)}k/sec) ") if (rand*1000).to_i == 0
      }
    }
  end

  def impactToDB(infile,vendor="walmart",logpath=STDOUT)
    logger=Logger.new(logpath)
    logger.info("importing to csv array")
    stego=DB.new()
    csv=CSV.new(Zlib::GzipReader.open(infile).read, headers: true,:col_sep=>"\t")
    logger.info("starting DB load")
      index=0
    while row=csv.shift
      begin
        next if !row[2].to_s.match(/\d+/) or !row[1].to_s.match(/\d+/)
        item={}
        item["item"]=row[3]
        item["brand"]=row[15]
        item["upc"]=row[2]
        item["price"]=row[1] 
        item["in-stock"]=true if row[34] == "InStock"
        item["in-stock"]=false if row[34] == "OutOfStock"
        item["sku"]=row[0]
        item["size"]=row[18] unless row[18].nil?
        item["color"]=row[17] unless row[17].nil?
        item["gender"]=row[11] unless row[11].nil?
        item["age-range"]=row[13] unless row[13].nil?
        item["image"]=row[6].match(/.+(\/.*(jp(e)?g|png|gif)).*/)[1]
        item["tags"]=row[24].split(" > ") rescue []
        item["tags"].push(row[37])
        stego.processItem(item,vendor)
        index+=1
        logger.info("#{index} upcs populated") if index % 50000 == 0
      rescue Exception => e
        #logger.debug(e)
        logger.error("error in #{e.backtrace[0]}, skipping #{item}")
        next
      end
    end
  end

  def impactParser(infile,outfile,logpath=STDOUT)
    stego={}
    logger=Logger.new(logpath)
    logger.info("extracting gz")
    file=Zlib::GzipReader.open(infile).read
    logger.info("import to csv array")
    csv=CSV.new(file, headers: true,:col_sep=>"\t")
    while item=csv.shift
      begin
        next unless item[2].to_s.match(/\d+/)
        unless stego[item[2]].nil?
          stego[item[2]]["prices"]=[] unless stego[item[2]]["prices"].class == Array
          stego[item[2]]["prices"].push(item[1])
          stego[item[2]]["price"] if item[35] == "InStock"
        else
          stego[item[2]]={}
          stego[item[2]]["prices"]=[]
        end
        stego[item[2]]["item"]=item[3]
        stego[item[2]]["brand"]=item[15]
        stego[item[2]]["upc"]=item[2]
        stego[item[2]]["price"]=item[1] if stego[item[2]]["price"].nil? 
        stego[item[2]]["in-stock"]=true if item[34] == "InStock"
        stego[item[2]]["in-stock"]=false if item[34] == "OutOfStock"
        stego[item[2]]["sku"]=item[0]
        stego[item[2]]["size"]=item[18] unless item[18].nil?
        stego[item[2]]["color"]=item[17] unless item[17].nil?
        stego[item[2]]["gender"]=item[11] unless item[11].nil?
        stego[item[2]]["age-range"]=item[13] unless item[13].nil?
        stego[item[2]]["image"]=item[6].match(/.+(\/.*(jp(e)?g|png|gif)).*/)[1]
        stego[item[2]]["tags"]=item[24].split(" > ") rescue []
        stego[item[2]]["tags"].push(item[37])
        logger.info("#{stego.size} upcs populated") if stego.size % 50000 == 0 
      rescue Exception => e
        #logger.debug(e)
        logger.error("error in #{e.backtrace[0]}, skipping #{item}")
        next
      end
    end
    logger.info("writing to #{outfile}")
    Zlib::GzipWriter.open(outfile) do |f|
      f.write(stego.to_json)
      f.close
    end
    return stego
  end
end
