require 'bundler'

Bundler.require

require 'rack'
require 'rack/mime'
require 'rack/contrib'
require 'rack/session/cookie'
require 'redis'
require 'yaml'
require 'json'

DOMAIN = "the-hold.kkbox.com"

module Rack
  module Session
    module Abstract
      class ID
        def set_cookie(env, headers, cookie)
          request = Rack::Request.new(env)
          if request.cookies[@key] != cookie[:value] || cookie[:expires]

            patten = Regexp.new("(?<version>\\d{8}-\\d{6})?\\.?(?<project>.+?)\\.(?<login>.+)\\.#{DOMAIN}$")
            project_route = request.host.match(patten)
            if project_route
                cookie[:domain] = ".#{project_route[:project]}.#{project_route[:login]}.#{DOMAIN}"
            else
                cookie[:domain] = request.host
            end

            Utils.set_cookie_header!(headers, @key, cookie)
          end
        end
      end
    end
  end
end

class TheHoldApp
  def initialize
    @base_path = "user_sites"
    @redis = Redis.new
  end

  def call(env)
    req = Rack::Request.new(env)

    return upload_file(req.params) if req.path == '/upload' && req.post?

    patten = Regexp.new("(?<version>\\d{8}-\\d{6})?\\.?(?<project>.+?)\\.(?<login>.+)\\.#{DOMAIN}$")
    project_route = req.host.match(patten)
    if project_route
        site_key = "site-#{project_route[:project]}.#{project_route[:login]}.#{DOMAIN}"
    else
        site_key = "site-#{req.host}"
        project_route={version: nil}
    end
    site   = @redis.hgetall(site_key)

    return not_found               if !( site["login"] && site["project"] )

    return login(env)              if need_auth?(env, req, site)

    return versions(site)          if req.path == '/__versions'
    return versions_json(site)          if req.path == '/__versions.json'

    current_project_path = File.join(@base_path, site["login"], site["project"], project_route[:version] || "current")
    path_info    = env["PATH_INFO"][-1] == '/' ? "#{env["PATH_INFO"]}index.html" : env["PATH_INFO"]
    if File.extname(path_info) == ""
      path_info += "/index.html" if File.directory?(  File.join( File.dirname(__FILE__), current_project_path,  path_info ) )
    end

    redirect_url = File.join(  "/", current_project_path,  path_info )
    mime_type = Rack::Mime.mime_type(File.extname(redirect_url), "text/html")
    [200, {"Cache-Control" => "public, must-revalidate, max-age=0, post-check=0, pre-check=30", 'Content-Type' => mime_type, 'X-Accel-Redirect' => redirect_url }, []]
  end

  def need_auth?(env, req, site)
    return false if req.path == '/manifest.json'
    return false if site["project_site_password"] == env["rack.session"]["password"]
    return false if !site["project_site_password"] || site["project_site_password"].empty?

    if req.post? && site["project_site_password"] == req.params["password"]
      env["rack.session"]["password"]= req.params["password"]
      return false
    end

    return true

  end

  def versions(site)
    project_hostname = "#{site["project"]}.#{site["login"]}.#{DOMAIN}"
    project_folder = File.join( @base_path, site["login"], site["project"])

    lis = Dir.glob("#{project_folder}/2*").to_a.sort.map{|d|
      d = File.basename(d)
      "<li><a href=\"http://#{d}.#{project_hostname}\">#{d}</a></li>"
    }
    body = "<ul>#{lis.join}</ul>"
    #[200, {"Content-Type" => "text/html"}, [body]]
    [200, { "Content-Type" => "text/html" }, [<<EOL
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Password Restricted Project</title>
<style>
html {
font-family: sans-serif;
-webkit-text-size-adjust: 100%;
-ms-text-size-adjust: 100%;
}
html,body {
    margin: 0;
    padding: 0;
}
.frames {
    position: relative;
}
.frame {
    float: left;
    width: 100%;
    height: 100%;
}
.frame iframe {
    width: 100%;
    height: 100%;
}

.frames-split .frame {
    width: 50%;
}
.frames-split .frame {
}
.frames-overlay .frame {
    position: absolute;
    top: 0;
    left: 0;
    opacity: 0.9;
}
.fireapp-toolbar {
    background: #e1e1e1;
    border-bottom: 1px solid #ddd;
    line-height: 30px;
}
.overlap, .frame-2 {
    display: none;
}
.brand {
    display: block;
    float: left;
    height: 30px;
    line-height: 30px;
    margin-right: 20px;
    background: #000;
    color: #fff;
    padding: 0 20px;
}
</style>
</head>
<body>
    <div id="fireapp-toolbar" class="fireapp-toolbar">
        <span class="brand">#{site["project"]}</span>
        <label>choose:</label>
        <select id="version-1">
        </select>
        <button type="button" id="btn-openwin" class="btn-openwin">open in new window</button>
        <label>compare with:</label>
        <select id="version-2">
            <option value="disable">&mdash;</option>
        </select>
        <label id="overlap" class="overlap"><input type="checkbox" name="overlap" value="1"> overlap</label>
    </div>
    <div id="frames" class="frames">
        <div id="frame-1" class="frame">
        </div>
        <div id="frame-2" class="frame">
        </div>
    </div>

<script src="http://ajax.googleapis.com/ajax/libs/jquery/1.9.1/jquery.min.js"></script>
<script>
$(function() {
    var i,
        opstr = '';

    $('#frame-2').hide();
    $('.frames').css("height", parseInt($(window).height(), 10) - parseInt($('#fireapp-toolbar').outerHeight(), 10) );

    $('#version-1').on('change', function() {
        $('#frame-1').empty().html('<iframe src="' + this.value + '"></iframe>');
    });
    $('#version-2').on('change', function() {
        if (this.value == 'disable') {
            $('#frame-2, #overlap').hide();
        } else {
            if ( !$('#frames').hasClass('frames-overlay') ) {
                $('#frames').addClass('frames-split');
            }
            $('#frame-2').empty().html('<iframe src="' + this.value + '"></iframe>');
            $('#frame-2, #overlap').show();
        }
    });

    $('#overlap input').on('change', function() {
        if ($(this).is(':checked')) {
            $('.frames').removeClass('frames-split');
            $('.frames').addClass('frames-overlay');
        } else {
            $('.frames').addClass('frames-split');
            $('.frames').removeClass('frames-overlay');
        }
    });

    $('#btn-openwin').on('click', function() {
        window.open($('#version-1').val());
    });

    $.getJSON('/__versions.json')
        .success(function(versions) {
            for (i = 0; i < versions.length; i++) {
                opstr += '<option value="' + versions[i].url + '">' + versions[i].name + '</option>';
            }
            $('.fireapp-toolbar select').append(opstr);
            $('#version-1').val( $('#version-1 option:first').val() ).trigger('change');
        });
});

</script>
</body>
</html>

EOL
    ]]
  end

  def versions_json(site)
    project_hostname = "#{site["project"]}.#{site["login"]}.#{DOMAIN}"
    project_folder = File.join( @base_path, site["login"], site["project"])

    list = Dir.glob("#{project_folder}/2*").to_a.sort.reverse.map{|d|
      d = File.basename(d)
      { name: Time.parse( d.gsub('-','') ).strftime('%Y/%m/%d %H:%M:%S'),
        url:  "http://#{d}.#{project_hostname}" }
    }

    body = JSON.dump(list)
    [200, {"Content-Type" => "text/html"}, [body]]
  end

  def upload_file(params)
    user_token_key = "user-#{params["login"]}"
    user_token  = @redis.get(user_token_key)
    return forbidden  unless user_token && user_token  == params["token"]

    project_folder = File.join( @base_path, params["login"], params["project"])
    project_folder = File.expand_path(project_folder)
    FileUtils.mkdir_p(project_folder)
    project_current_folder = File.join(project_folder, "current")


    tempfile_path  = params["patch_file"][:tempfile].path
    to_folder = File.join( project_folder, Time.now.strftime("%Y%m%d-%H%M%S") )
    %x{unzip #{tempfile_path} -d #{to_folder}}

    to_json_file = File.join(to_folder, 'manifest.json')
    to_json_data = open(to_json_file,'r'){|f| f.read}
    to = JSON.load( to_json_data )

    to.each do |filename, md5|
      to_filename = File.join(to_folder, filename)
      if !File.exists?(to_filename)
        FileUtils.mkdir_p(File.dirname(to_filename))
        form_filename = File.join( project_current_folder, filename )
        if form_filename.index(project_folder) && to_filename.index(project_folder)
          next if !File.exists?(form_filename)
          File.link(form_filename, to_filename)
        end
      end
    end

    File.unlink( project_current_folder ) if File.exists?( project_current_folder )
    File.symlink(to_folder, project_current_folder )

    project_hostname = "#{params["project"]}.#{params["login"]}.#{DOMAIN}"
    @redis.hmset("site-#{project_hostname}", :login, params["login"], :project, params["project"] );

    if params["cname"] && !params["cname"].empty?
      cname = params["cname"]
      begin
        dns = Resolv::DNS.new
        target_record = dns.getresources(cname, Resolv::DNS::Resource::IN::CNAME).first
        if target_record && target_record.name.to_s == project_hostname
          @redis.hmset("site-#{cname}",       :login, params["login"], :project, params["project"] );
        end
      end
    end

    if params["project_site_password"] && !params["project_site_password"].empty?
      password = params["project_site_password"][0,64]
      @redis.hset("site-#{cname}", "project_site_password", password ) if cname
      @redis.hset("site-#{project_hostname}", 'project_site_password', password);
    else
      @redis.hdel("site-#{cname}", "project_site_password" ) if cname
      @redis.hdel("site-#{project_hostname}", 'project_site_password');
    end

    [200, {"Content-Type" => "text/plain"}, ["ok"]]
  end

  def not_found
    [404, {'Content-Type' => 'text/plain' }, ["Not Found"]]
  end

  def forbidden
    [403, {'Content-Type' => 'text/plain' }, ["Forbidden"]]
  end

  def login(env)
    [200, { "Content-Type" => "text/html" }, [<<EOL
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Password Restricted Project</title>
<style>
html {
font-family: sans-serif;
-webkit-text-size-adjust: 100%;
-ms-text-size-adjust: 100%;
}
body {
margin: 0;
padding: 0;
background: #f1f1f1;
}
.container {
position: absolute;
width: 300px;
margin-left: -150px;
left: 50%;
top: 100px;
text-align: center;
}

label, input, button {
display: block;
font-size: 24px;
line-height: 24px;
}

label {
margin: 0 auto;
}

input, button {
box-sizing: border-box;
}

input {
width: 100%;
margin: 12px auto;
padding: 5px;
}
button {
margin: 0 auto;
width: 100%;
border:1px solid #25729a; -webkit-border-radius: 3px; -moz-border-radius: 3px;border-radius: 3px;font-family:arial, helvetica, sans-serif; padding: 10px 10px 10px 10px; text-shadow: -1px -1px 0 rgba(0,0,0,0.3);font-weight:bold; text-align: center; color: #FFFFFF; background-color: #3093c7;
background-image: -webkit-gradient(linear, left top, left bottom, color-stop(0%, #3093c7), color-stop(100%, #1c5a85));
background-image: -webkit-linear-gradient(top, #3093c7, #1c5a85);
background-image: -moz-linear-gradient(top, #3093c7, #1c5a85);
background-image: -ms-linear-gradient(top, #3093c7, #1c5a85);
background-image: -o-linear-gradient(top, #3093c7, #1c5a85);
background-image: linear-gradient(top, #3093c7, #1c5a85);filter:progid:DXImageTransform.Microsoft.gradient(GradientType=0,startColorstr=#3093c7, endColorstr=#1c5a85);
}

button:hover{
border:1px solid #1c5675; background-color: #26759e;
background-image: -webkit-gradient(linear, left top, left bottom, color-stop(0%,#26759e), color-stop(100%, #133d5b));
background-image: -webkit-linear-gradient(top, #26759e, #133d5b);
background-image: -moz-linear-gradient(top, #26759e, #133d5b);
background-image: -ms-linear-gradient(top, #26759e, #133d5b);
background-image: -o-linear-gradient(top, #26759e, #133d5b);
background-image: linear-gradient(top, #26759e, #133d5b);filter:progid:DXImageTransform.Microsoft.gradient(GradientType=0,startColorstr=#26759e, endColorstr=#133d5b);
}
</style>
</head>
<body>
<div class="container">
<form action="#{env["PATH_INFO"]}" method="post">
<label>Password</label>
<input type="password" name="password" size="16" autofocus>
<button type="submit">Let me in!</button>
</form>
</div>
</body>
</html>
EOL
    ]]
  end

end

use Rack::Session::Cookie, :secret => 'SECRET TOKEN'
raise "replace SECRET TOKEN"

run TheHoldApp.new

