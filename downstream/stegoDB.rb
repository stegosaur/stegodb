require 'json'
require 'yaml'
require 'sequel'
require 'logger'

$config=YAML.load_file("#{$LOAD_PATH[0]}/config.yml")
$db=Sequel.connect("mysql2://#{$config['dbUser']}:#{$config['dbPass']}@#{$config['dbHost']}:3306/#{$config['dbName']}")
$logger=Logger.new(STDOUT)

class DB
  def addNewItem(brand,tags)
    return $db[:items].insert(:brand => brand, :tags => tags.sort.uniq.to_json, :firstSeen => Time.now)
  end
  def addNewUPC(upc,id,name,size,price,vendor)
    return $db[:upcs].insert(:upc => upc, :id => id, :name => name, :size => size, :price => price, :vendors => [vendor].to_json)
  end
  def addNewImage(id,alt,src)
    return $db[:images].insert(:id => id, :alt => alt, :src => src )
  end
  def addNewURL(id,url,vendor)
    return $db[:urls].insert(:id => id, :url => url, :vendor => vendor)
  end
  def addHistory(upc,id,vendor,price)
    return $db[:history].insert(:upc => upc, :id => id, :vendor => vendor, :price => price)
  end
  def mergeTags(id,tags)
    current=$db[:items].select(:tags).where(:id => id).map{|x| x[:tags] }
    merged=(current + tags).sort.uniq
    return $db[:items].where(:id => id).update(:tags => merged.to_json)
  end
  def getIDbyUPC(upc)
    return $db[:upcs].select(:id).where(:upc => upc).map{|x| x[:id] }[0]
  end
  def getIDbyImage(image)
    return $db[:images].select(:id).where(:src => image).map{|x| x[:id] }[0]
  end
  def getImages(id)
    return $db[:images].select(:src).where(:id => id).map{|x| x[:src] }
  end
  def getURLs(id=nil,upc=nil)
    raise "id or upc required" if id.nil? and upc.nil?
    id=getIDbyUPC(upc) if id.nil?
    return $db[:urls].select(:url).where(:id=>id).map{|x| x[:url]}
  end
  def getNeighborsByImage(image)
    id=getIDbyImage(image)
    return $db[:upcs].where(id: id).map{|u| u[:upc]}
  end

  def processItem(item,vendor)
    #get the item id
    begin
      item["item"]=item["item"][0..254]
      item["size"]=item["size"][0..254] unless item["size"].nil?
      loggable="#{[item["brand"],item["item"],item["price"],item["upc"],item["size"],vendor]}"
      id=getIDbyUPC(item["upc"])
      if id.nil?
        id=getIDbyImage(item["image"])
        $logger.debug("found item id #{id} from image #{item["image"]}") unless id.nil?
      else
        $logger.debug("found item id #{id} from upc #{item["upc"]}")
      end
      if id.nil? #new item found
        id=addNewItem(item["brand"],item["tags"])
        addNewUPC(item["upc"],id,item["item"],item["size"],item["price"],vendor)
        addNewImage(id,alt="#{vendor}#{Time.now.strftime("%s")}",src=item["image"])
        addNewURL(id,url=item["sku"],vendor)
        #$logger.info("new item added with id #{id}: #{[ item["brand"],item["item"],item["price"],item["upc"],item["size"],vendor ] }")
      else #item exists, run updates if any
        images=getImages(id)
        urls=getURLs(id)
        addNewUPC(item["upc"],id,item["item"],item["size"],item["price"],vendor) unless getIDbyUPC(item["upc"])
        addNewImage(id,alt="#{vendor}#{Time.now.strftime("%s")}",src=item["image"]) unless images.include?(item["image"])
        $logger.info("urls: #{urls.join(",")} include? #{item["sku"]} #{urls.include?(item["sku"])} ")
        addNewURL(id,url=item["sku"],vendor) unless urls.include?(item["sku"])
        #mergeTags(id,item["tags"])
      end
      addHistory(item["upc"],id,vendor,item["price"]) if item["in-stock"] == true
    rescue Exception => e
      $logger.error(e)
    end
  end
end
