#
# Cookbook Name:: native
# Recipe:: default
#
# Copyright 2017, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
%w{autoconf ntp bison pygpgme curl flex wget gcc gcc-c++ kernel-devel make m4}.each do |pkg|
   package pkg
end
