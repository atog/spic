require 'rubygems'
require 'sinatra'
require 'sinatra/sequel'
require 'carrierwave'
require 'flickr_fu'

ROOT = Dir.pwd

configure do
  if File.exist?("settings.yml")
    @@settings = YAML.load_file("settings.yml")
  else
    @@settings = {
      "s3_access_key_id" => ENV['S3_KEY'],
      "s3_secret_access_key" => ENV['S3_SECRET'],
      "s3_bucket" => ENV['S3_BUCKET'],
      "secret" => ENV['SECRET'],
      "flickr_key" => ENV['FLICKR_KEY'],
      "flickr_secret" => ENV["FLICKR_SECRET"]
    }
  end
  CarrierWave.configure do |config|
    config.s3_access_key_id = @@settings["s3_access_key_id"]
    config.s3_secret_access_key = @@settings["s3_secret_access_key"]
    config.s3_bucket = @@settings["s3_bucket"]
  end
end

# Establish the database connection; or, omit this and use the DATABASE_URL
# environment variable as the connection string:
# set :database, @@settings["db_url"]

# define database migrations. pending migrations are run at startup and
# are guaranteed to run exactly once per database.
migration "create images table" do
  database.create_table :images do
    primary_key :id
    text        :name
    timestamp   :created_at, :allow_null => false
    boolean     :flickr, :default => false
    index :name
  end
end

migration "create flickr token table" do
  database.create_table :tokens do
    primary_key :id
    text :token
  end
end

class FlickrStorage < CarrierWave::Storage::Abstract

  def store!(file)
    flickr = Flickr.new({
                          :key => @@settings["flickr_key"],
                          :secret => @@settings["flickr_secret"],
                          :token => Token.order(:id.asc).last.token
                        })
    flickr.uploader.upload(file.path, :tags => "spic")
  rescue StandardError => e
    puts "PAKOT: #{e}"
    puts e.backtrace.join("\n")
  end

end

class ImageUploader < CarrierWave::Uploader::Base
  # storage :right_s3 #european bucket
  storage FlickrStorage

  def store_dir
     nil  #store files at root level
  end

  def cache_dir
    "#{ROOT}/tmp/"
  end

end

class Token < Sequel::Model; end

class Image < Sequel::Model
  mount_uploader :name, ImageUploader

  def url #Using @image.name.url gives a AWS S3 PermanentRedirect
    "http://#{@@settings["s3_bucket"]}.s3.amazonaws.com/#{self.name.path}"
  end
end

get '/' do
  erb :index
end

get '/u/*' do
  if params[:splat]
    @image = Image.find(:id => params[:splat].first)
    erb :url
  else
    redirect '/'
  end
end

get "/#{@@settings["secret"]}" do
  @secret = @@settings["secret"]
  @images = Image.order(:id.desc)
  erb :secret
end

post '/p' do
  if @@settings["secret"] == params[:secret]
    image = Image.create(:name => params[:name], :created_at => Time.now)
  end
  redirect "/u/#{image.id}"
end

post '/d' do
  if (@@settings["secret"] == params[:secret]) && (@image = Image.find(:id => params[:id]))
    @image.destroy
  end
  redirect '/'
end

get '/flickr-authenticate' do
  flickr = Flickr.new({:key => @@settings["flickr_key"], :secret => @@settings["flickr_secret"]})
  redirect flickr.auth.url(:write)
end

get '/flickr-callback' do
  flickr = Flickr.new({:key => @@settings["flickr_key"], :secret => @@settings["flickr_secret"]})
  flickr.auth.frob = params[:frob]
  Token.create(:token => flickr.auth.token.token)
  erb :flickr_success
end

__END__

@@ index
<h1>SPIC</h1>

@@ secret
<form action="/p" method="POST" enctype="multipart/form-data">
  <input type='hidden' name='secret' value='<%= @secret %>' />
  <input type='file' name="name" />
  <input type='submit'/>
</form>

<ul>
  <% @images.each do |image| %>
  <li>
    <a href="<%=image.url%>"><%= image.name.path %></a> -
    <a href="#" onclick="document.forms['i-<%= image.id %>'].submit();">delete</a>
    <form action="/d" method="POST" id="i-<%= image.id %>">
      <input type='hidden' name='secret' value='<%= @secret %>' />
      <input type='hidden' name='id' value='<%= image.id %>' />
    </form>
  </li>
  <% end %>
</ul>

@@ url
<%=@image.url if @image %>

@@ flickr_success
<p>Flickr Authentication Success!</p>
