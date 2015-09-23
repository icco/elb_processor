require "rubygems"
require "bundler"
Bundler.require(:default, ENV["RACK_ENV"] || :development)
require 'fileutils'

ACCESS_KEY_ID = "AKIAJXUQJGETN7NZQNDA"
SECRET_ACCESS_KEY = "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"

def percentile(values, percentile)

  raise "Percentile must be < 1." if percentile > 1

  values_sorted = values.sort
  k = (percentile*(values_sorted.length-1)+1).floor - 1
  f = (percentile*(values_sorted.length-1)+1).modulo(1)

  return values_sorted[k] + (f * (values_sorted[k+1] - values_sorted[k]))
end

# Other ideas: https://gist.github.com/meinside/9461552

year = 2015
month = 8
prefix = "web-railsapp-production/AWSLogs/894935469341/elasticloadbalancing/us-east-1/#{year}/#{'%02i' % month}"

# ELB Log Format
# timestamp elb client:port backend:port request_processing_time backend_processing_time response_processing_time elb_status_code backend_status_code received_bytes sent_bytes "request" "user_agent" ssl_cipher ssl_protocol
# "2015-07-31T23:59:59.852432Z web-railsapp-production 141.101.98.30:27548 172.30.1.199:80 0.000052 0.078216 0.000036 200 200 220 2 \"POST http://littlebits.cc:80/ahoy/events HTTP/1.1\" \"Mozilla/5.0 (iPad; CPU OS 8_4 like
# http://httpd.apache.org/docs/2.2/mod/mod_log_config.html
format = '%t %{ELB}n %a:{remote}p %A:{local}p %{request_processing_time}n %{backend_processing_time}n %{response_processing_time}n %{elb_status_code}n %{backend_status_code}n %{received_bytes}n %{sent_bytes}n \"%r\" \"%{User-Agent}i\" - -'
parser = ApacheLogRegex.new(format)

service = Fog::Storage.new({:provider => 'AWS', :aws_access_key_id => ACCESS_KEY_ID, :aws_secret_access_key => SECRET_ACCESS_KEY})

dir = service.directories.get("littlebits-logs")
files = Fog::Storage::AWS::Files.new(directory: dir, service: service, prefix: prefix, max_keys: 10000)

request_data = Hash.new { |h, k| h[k] = [] }

files.each do |s3_file|
  puts " - Parsing #{s3_file.key}"

  if !File.exist? s3_file.key
    dirname = File.dirname(s3_file.key)
    unless File.directory?(dirname)
      FileUtils.mkdir_p(dirname)
    end

    File.open(s3_file.key, 'w') do |local_file|
      local_file.write(s3_file.body)
    end
  end

  File.open(s3_file.key, "r").each_line do |l|
    data, request, user_data = l.encode('UTF-8', :invalid => :replace).split('"').delete_if {|i| i == " " }

    data = data.split " "

    time = Chronic.parse(data[0]) # "2015-08-01T00:00:48.828256Z"
    elb = data[1] # "web-railsapp-production"
    source = data[2] # "108.162.246.227:27442"
    backend = data[3] # "172.30.1.51:80"
    request_processing_time = data[4].to_f # "0.000045"
    backend_processing_time = data[5].to_f # "0.766932"
    response_processing_time = data[6].to_f # "0.000044"
    elb_status_code = data[7].to_i # "200"
    backend_status_code = data[8].to_i # "200"
    received_bytes = data[9].to_i # "0"
    sent_bytes = data[10].to_i  # "20219"


    request_data[request] << backend_processing_time
  end

  more_than_ten = request_data.select {|k,v| v.size > 100 }
  more_than_ten.to_a.map {|k,v| [k, percentile(v, 0.90)] }.sort {|a,b| a[1] <=> b[1] }.each do |k, v|
    puts "#{k} \t => \t #{v}"
  end
end

more_than_ten = request_data.select {|k,v| v.size > 10 }
more_than_ten.to_a.map {|k,v| [k, percentile(v, 0.90)] }.sort {|a,b| a[1] <=> b[1] }.each do |k, v|
  puts "#{k} \t => \t #{v}"
end
