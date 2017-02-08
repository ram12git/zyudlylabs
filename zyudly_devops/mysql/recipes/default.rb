#
# Cookbook Name:: mysql
# Recipe:: default
#
# Copyright 2016, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

package 'mysql-server' do
action :install
end

service 'mysqld' do
 action [:enable, :start]
end

template "/etc/yum.repos.d/mysql.repo" do
  source 'mysql.repo.erb'
end
