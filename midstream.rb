$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__))) unless $LOAD_PATH.include?(File.expand_path(File.dirname(__FILE__)))
require 'yaml'
$config=YAML.load_file("./config.yml")
require 'optparse'
require 'midstream/stegoDB'

# midstream: processing of data
$logger=Logger.new(STDOUT)

options={}
OptionParser.new do |opts|
  opts.on("-w", "--watch=value", String) { |value| options['watch'] = value }
  opts.on("-v", "--vendor=value", String) { |value| options['vendor'] == value }
  opts.on("-f", "--file=value", String) { |value| options['file'] == value }
end.parse!
raise 'usage: pipeline.rb -w <watch path> -v <vendor>' if options['watch'].nil? or options['vendor'].nil?

def process(file)
  t0=Time.now
  $logger.info("processing file #{file}...")
  File.rename(file,file+".processing")
  impactToDB(file+".processing",vendor=options['vendor'])
  File.delete(file+".processing")
  $logger.info("#{file} was processed in #{((Time.now-t0)/60.0/60.0).round(2)} hours"
end

if options['file'].nil?
  Dir["#{options['watch']}/*.gz"].each{|file|
    process(file)
  }
else
  process(file)
end
