#
# Cookbook Name:: nginxpassenger
# Recipe:: default
#
# Copyright 2016, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
%w{ epel-release yum-utils pygpgme curl}.each do |pkg|
  package pkg
end
execute "yum-config-manager --enable epel"

 execute "sudo curl --fail -sSLo /etc/yum.repos.d/passenger.repo https://oss-binaries.phusionpassenger.com/yum/definitions/el-passenger.repo"
 execute "sudo yum install -y nginx passenger"

service 'nginx' do
  action [:enable, :start]
end

