#
# Cookbook Name:: ruby
# Recipe:: default
#
# Copyright 2016, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

%w{git-core zlib zlib-devel gcc-c++ patch readline readline-devel libyaml-devel libffi-devel openssl-devel make bzip2 autoconf automake libtool bison curl sqlite-devel }.each do |pkg|
  package pkg
end


bash 'extract_module' do
    code <<-EOH
    cd /opt/
  wget https://cache.ruby-lang.org/pub/ruby/2.3/ruby-2.3.0.tar.bz2
    tar -xvjf ruby-2.3.0.tar.bz2
    cd ruby-2.3.0
    ./configure
    make
    make install
    EOH
end
