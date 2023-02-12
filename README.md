# Meshcentral-Installer
Install Script for Meshcentral 

### Installs meshcentral, giving the options of database to use and setups up defaults, branding, ssl etc.

modified extensively from  the original https://github.com/techahold/Meshcentral-Installer

data collection at the beginning of the script
optimisation for apt-get
optimisation for starting and stopping meshcentral
no choice about LetsEncrypt
adds the hostname for letsencrypt to teh hosts file
using a meshcentral account instead of the logged on user
only using mongodb
still has a choice for the company & group parts
