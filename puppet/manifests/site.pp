# test
#
# one machine setup with weblogic 12.1.2 with OPatch
# needs jdk7, orawls, orautils, fiddyspence-sysctl, erwbgy-limits puppet modules
#

node 'adminwls.example.com' {
  
  include os, ssh, java, mysql
  include orawls::weblogic, orautils
  include opatch
  include domains, nodemanager, startwls, userconfig
  include machines, datasources
  include pack_domain

  Class[java] -> Class[orawls::weblogic]
}  

# operating settings for Middleware
# operating settings for Middleware
class os {

  notice "class os ${operatingsystem}"

  $default_params = {}
  $host_instances = hiera('hosts', [])
  create_resources('host',$host_instances, $default_params)

  exec { "create swap file":
    command => "/bin/dd if=/dev/zero of=/var/swap.1 bs=1M count=8192",
    creates => "/var/swap.1",
  }

  exec { "attach swap file":
    command => "/sbin/mkswap /var/swap.1 && /sbin/swapon /var/swap.1",
    require => Exec["create swap file"],
    unless => "/sbin/swapon -s | grep /var/swap.1",
  }

  #add swap file entry to fstab
  exec {"add swapfile entry to fstab":
    command => "/bin/echo >>/etc/fstab /var/swap.1 swap swap defaults 0 0",
    require => Exec["attach swap file"],
    user => root,
    unless => "/bin/grep '^/var/swap.1' /etc/fstab 2>/dev/null",
  }

  service { iptables:
        enable    => false,
        ensure    => false,
        hasstatus => true,
  }

  group { 'dba' :
    ensure => present,
  }

  # http://raftaman.net/?p=1311 for generating password
  # password = oracle
  user { 'oracle' :
    ensure     => present,
    groups     => 'dba',
    shell      => '/bin/bash',
    password   => '$1$DSJ51vh6$4XzzwyIOk6Bi/54kglGk3.',
    home       => "/home/oracle",
    comment    => 'oracle user created by Puppet',
    managehome => true,
    require    => Group['dba'],
  }

  $install = [ 'binutils.x86_64','unzip.x86_64']


  package { $install:
    ensure  => present,
  }

  class { 'limits':
    config => {
               '*'       => {  'nofile'  => { soft => '2048'   , hard => '8192',   },},
               'oracle'  => {  'nofile'  => { soft => '65536'  , hard => '65536',  },
                               'nproc'   => { soft => '2048'   , hard => '16384',   },
                               'memlock' => { soft => '1048576', hard => '1048576',},
                               'stack'   => { soft => '10240'  ,},},
               },
    use_hiera => false,
  }

  sysctl { 'kernel.msgmnb':                 ensure => 'present', permanent => 'yes', value => '65536',}
  sysctl { 'kernel.msgmax':                 ensure => 'present', permanent => 'yes', value => '65536',}
  sysctl { 'kernel.shmmax':                 ensure => 'present', permanent => 'yes', value => '2588483584',}
  sysctl { 'kernel.shmall':                 ensure => 'present', permanent => 'yes', value => '2097152',}
  sysctl { 'fs.file-max':                   ensure => 'present', permanent => 'yes', value => '6815744',}
  sysctl { 'net.ipv4.tcp_keepalive_time':   ensure => 'present', permanent => 'yes', value => '1800',}
  sysctl { 'net.ipv4.tcp_keepalive_intvl':  ensure => 'present', permanent => 'yes', value => '30',}
  sysctl { 'net.ipv4.tcp_keepalive_probes': ensure => 'present', permanent => 'yes', value => '5',}
  sysctl { 'net.ipv4.tcp_fin_timeout':      ensure => 'present', permanent => 'yes', value => '30',}
  sysctl { 'kernel.shmmni':                 ensure => 'present', permanent => 'yes', value => '4096', }
  sysctl { 'fs.aio-max-nr':                 ensure => 'present', permanent => 'yes', value => '1048576',}
  sysctl { 'kernel.sem':                    ensure => 'present', permanent => 'yes', value => '250 32000 100 128',}
  sysctl { 'net.ipv4.ip_local_port_range':  ensure => 'present', permanent => 'yes', value => '9000 65500',}
  sysctl { 'net.core.rmem_default':         ensure => 'present', permanent => 'yes', value => '262144',}
  sysctl { 'net.core.rmem_max':             ensure => 'present', permanent => 'yes', value => '4194304', }
  sysctl { 'net.core.wmem_default':         ensure => 'present', permanent => 'yes', value => '262144',}
  sysctl { 'net.core.wmem_max':             ensure => 'present', permanent => 'yes', value => '1048576',}

}

class ssh {
  require os

  notice 'class ssh'

  file { "/home/oracle/.ssh/":
    owner  => "oracle",
    group  => "dba",
    mode   => "700",
    ensure => "directory",
    alias  => "oracle-ssh-dir",
  }
  
  file { "/home/oracle/.ssh/id_rsa.pub":
    ensure  => present,
    owner   => "oracle",
    group   => "dba",
    mode    => "644",
    source  => "/vagrant/ssh/id_rsa.pub",
    require => File["oracle-ssh-dir"],
  }
  
  file { "/home/oracle/.ssh/id_rsa":
    ensure  => present,
    owner   => "oracle",
    group   => "dba",
    mode    => "600",
    source  => "/vagrant/ssh/id_rsa",
    require => File["oracle-ssh-dir"],
  }
  
  file { "/home/oracle/.ssh/authorized_keys":
    ensure  => present,
    owner   => "oracle",
    group   => "dba",
    mode    => "644",
    source  => "/vagrant/ssh/id_rsa.pub",
    require => File["oracle-ssh-dir"],
  }        
}

class java {
  require os

  notice 'class java'

  $remove = [ "java-1.7.0-openjdk.x86_64", "java-1.6.0-openjdk.x86_64" ]

  package { $remove:
    ensure  => absent,
  }

  include jdk7

  jdk7::install7{ 'jdk1.7.0_45':
      version              => "7u45" , 
      fullVersion          => "jdk1.7.0_45",
      alternativesPriority => 18000, 
      x64                  => true,
      downloadDir          => "/data/install",
      urandomJavaFix       => true,
      sourcePath           => "/vagrant",
  }

}

class mysql {
  require os

  class { '::mysql::server':
    root_password    => 'welcome',
    override_options => { 
          'mysqld' => { 
            'max_connections'   => '1024' ,
            'bind_address'      => '10.10.10.10',
          } 
      },
    users  => { 
          'scott@%' => {
            ensure                   => 'present',
            password_hash            => '*F2F68D0BB27A773C1D944270E5FAFED515A3FA40',
          },
          'jms@%' => {
            ensure                   => 'present',
            password_hash            => '*28CA77A6A0BB78326F4FB9832227B7B30EC1F167',
          },
          'wls@%' => {
            ensure                   => 'present',
            password_hash            => '*8004AA0A8F787363411605114E740FD69D34642F',
          },         
          'scott@adminwls' => {
            ensure                   => 'present',
            password_hash            => '*F2F68D0BB27A773C1D944270E5FAFED515A3FA40',
          },
          'jms@adminwls' => {
            ensure                   => 'present',
            password_hash            => '*28CA77A6A0BB78326F4FB9832227B7B30EC1F167',
          },
          'wls@adminwls' => {
            ensure                   => 'present',
            password_hash            => '*8004AA0A8F787363411605114E740FD69D34642F',
          },         
          'scott@nodewls1' => {
            ensure                   => 'present',
            password_hash            => '*F2F68D0BB27A773C1D944270E5FAFED515A3FA40',
          },
          'jms@nodewls1' => {
            ensure                   => 'present',
            password_hash            => '*28CA77A6A0BB78326F4FB9832227B7B30EC1F167',
          },
          'wls@nodewls1' => {
            ensure                   => 'present',
            password_hash            => '*8004AA0A8F787363411605114E740FD69D34642F',
          },         
          'scott@nodewls2' => {
            ensure                   => 'present',
            password_hash            => '*F2F68D0BB27A773C1D944270E5FAFED515A3FA40',
          },
          'jms@nodewls2' => {
            ensure                   => 'present',
            password_hash            => '*28CA77A6A0BB78326F4FB9832227B7B30EC1F167',
          },
          'wls@nodewls2' => {
            ensure                   => 'present',
            password_hash            => '*8004AA0A8F787363411605114E740FD69D34642F',
          },         

      },
    grants => {
          'scott@%' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'scott.*',
            user       => 'scott@%',
          },
          'jms@%' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['CREATE','DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'jms.*',
            user       => 'jms@%',
          },
          'wls@%' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['CREATE','DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'wls.*',
            user       => 'wls@%',
          },          
          'scott@adminwls' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'scott.*',
            user       => 'scott@adminwls',
          },
          'jms@adminwls' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['CREATE','DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'jms.*',
            user       => 'jms@adminwls',
          },
          'wls@adminwls' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['CREATE','DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'wls.*',
            user       => 'wls@adminwls',
          },          
          'scott@nodewls1' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'scott.*',
            user       => 'scott@nodewls1',
          },
          'jms@nodewls1' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['CREATE','DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'jms.*',
            user       => 'jms@nodewls1',
          },
          'wls@nodewls1' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['CREATE','DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'wls.*',
            user       => 'wls@nodewls1',
          },  
          'scott@nodewls2' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'scott.*',
            user       => 'scott@nodewls2',
          },
          'jms@nodewls2' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['CREATE','DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'jms.*',
            user       => 'jms@nodewls2',
          },
          'wls@nodewls2' => {
            ensure     => 'present',
            options    => ['GRANT'],
            privileges => ['CREATE','DROP','ALTER','SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            table      => 'wls.*',
            user       => 'wls@nodewls2',
          },  
      },  
    databases => {
          'scott' => {
            ensure  => 'present',
            charset => 'utf8',
          },
          'jms' => {
            ensure  => 'present',
            charset => 'utf8',
          },
          'wls' => {
            ensure  => 'present',
            charset => 'utf8',
          },
      },  
    service_enabled => true,   

  }


  exec {"add scott data":
    command   => "/usr/bin/sudo /usr/bin/mysql scott -u root < /vagrant/scott_tiger_data.sql",
    require   => Class['mysql::server'],
    user      => vagrant,
    group     => vagrant,
    logoutput => true,
  }


}

class opatch{
  require orawls::weblogic

  notice 'class opatch'
  $default_params = {}
  $opatch_instances = hiera('opatch_instances', [])
  create_resources('orawls::opatch',$opatch_instances, $default_params)
}

class domains{
  require orawls::weblogic, opatch

  notice 'class domains'
  $default_params = {}
  $domain_instances = hiera('domain_instances', [])
  create_resources('orawls::domain',$domain_instances, $default_params)
}

class nodemanager {
  require orawls::weblogic, domains

  notify { 'class nodemanager':} 
  $default_params = {}
  $nodemanager_instances = hiera('nodemanager_instances', [])
  create_resources('orawls::nodemanager',$nodemanager_instances, $default_params)
}

class startwls {
  require orawls::weblogic, domains,nodemanager


  notify { 'class startwls':} 
  $default_params = {}
  $control_instances = hiera('control_instances', [])
  create_resources('orawls::control',$control_instances, $default_params)
}

class userconfig{
  require orawls::weblogic, domains, nodemanager, startwls 

  notify { 'class userconfig':} 
  $default_params = {}
  $userconfig_instances = hiera('userconfig_instances', [])
  create_resources('orawls::storeuserconfig',$userconfig_instances, $default_params)
} 

class machines{
  require userconfig

  notify { 'class machines':} 
  $default_params = {}
  $machines_instances = hiera('machines_instances', [])
  create_resources('orawls::wlstexec',$machines_instances, $default_params)
}

class datasources{
  require machines

  $default_params = {}
  $datasource_instances = hiera('datasource_instances', [])
  create_resources('orawls::wlstexec',$datasource_instances, $default_params)
}

class pack_domain{
  require datasources

  notify { 'class pack_domain':} 
  $default_params = {}
  $pack_domain_instances = hiera('pack_domain_instances', $default_params)
  create_resources('orawls::packdomain',$pack_domain_instances, $default_params)
}

