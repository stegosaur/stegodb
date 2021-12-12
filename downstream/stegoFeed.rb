#!/usr/bin/env ruby
$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__))) unless $LOAD_PATH.include?(File.expand_path(File.dirname(__FILE__)))
require 'pp'
require 'csv'
require 'json'
require 'yaml'
require 'net/ftp'
require 'logger'
require 'zlib'
require '../midstream/stegoDB'
raise '$config is undefined' if $config.nil?

class Feeder
  def impactFTP(outpath,ftpHost=$config['ftpHost'],ftpUser=$config['ftpUser'],ftpPass=$config['ftpPass'])
    ftp=Net::FTP.open(ftpHost)
    ftp.read_timeout=300
    ftp.login(ftpUser,ftpPass)
    files = ftp.chdir("/Walmart-Affiliate-Program/")
    files = ftp.list('*CUSTOM*').map{|f| f.split(" ")[-1]}
    files.each{|file|
      t0=Time.now
      transferred=0
      outfile="#{outpath}/#{Time.now.to_i}.#{file}"
      ftp.getbinaryfile(file, outfile, 1024*1) { |data|
        transferred += data.size
        $logger.info("downloading #{outfile} #{(transferred/1024.0/1024.0).round(4)}mb (#{(transferred/(Time.now-t0)/1024).round(2)}k/sec) ") if (rand*1000).to_i == 0
      }
    }
  end

  def impactToDB(infile,vendor="walmart")
    $logger.info("processing csv #{infile} for #{vendor}")
    stego=DB.new()
    gz=Zlib::GzipReader.new(open(infile))
    index=0
    t0=Time.now
    while output = gz.gets
      begin
        row=CSV.new(output, :col_sep=>"\t").shift
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
        item["image"]=row[6].match(/.+(\/.*(jp(e)?g|png|gif)).*/)[1] rescue next
        item["tags"]=row[24].split(" > ") rescue []
        item["tags"].push(row[37])
        stego.processItem(item,vendor)
        index+=1
        $logger.info("#{index} upcs populated in #{((Time.now-t0)/60.0).round(2)} minutes (#{index/(Time.now-t0)} upcs processed/sec)") if index % 10000 == 0
      rescue Exception => e
        #$logger.debug(e)
        $logger.error("error in #{e.backtrace[0]}, skipping #{item}")
        next
      end
    end
  end
end
