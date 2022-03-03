# This plan is in development and currently considered experimental.
#
# @api private
#
# @summary Destructively (re)populates a new or existing database with the contents or a known good source
# @param source_host _ The hostname of the database containing data
# @param destination_host _ The hostname of the database to be (re)populated
plan peadm::subplans::db_populate(
  Peadm::SingleTargetSpec $targets,
  Peadm::SingleTargetSpec $source_host,
){
  $source_target      = peadm::get_targets($source_host, 1)
  $destination_target = peadm::get_targets($targets, 1)

  #  Stop puppet
  run_command('systemctl stop puppet.service', peadm::flatten_compact([
    $source_target,
    $destination_target,
  ]))

  # Add the following two lines to /opt/puppetlabs/server/data/postgresql/11/data/pg_ident.conf
  # 
  apply($source_target) {
    file_line { 'replication-pe-ha-replication-map':
      path => '/opt/puppetlabs/server/data/postgresql/11/data/pg_ident.conf',
      line => "replication-pe-ha-replication-map ${destination_target.peadm::certname()} pe-ha-replication",
    }
    file_line { 'replication-pe-ha-replication-ipv4':
      path => '/opt/puppetlabs/server/data/postgresql/11/data/pg_hba.conf',
      line => 'hostssl replication    pe-ha-replication 0.0.0.0/0  cert  map=replication-pe-ha-replication-map  clientcert=1',
    }
    file_line { 'replication-pe-ha-replication-ipv6':
      path => '/opt/puppetlabs/server/data/postgresql/11/data/pg_hba.conf',
      line => 'hostssl replication    pe-ha-replication ::/0       cert  map=replication-pe-ha-replication-map  clientcert=1',
    }
  }

  # Reload pe-postgresql.service
  run_command('systemctl reload pe-postgresql.service', $source_target)

  run_command('mv /opt/puppetlabs/server/data/postgresql/11/data/certs /opt/puppetlabs/server/data/pg_certs', $destination_target)

  run_command('rm -rf /opt/puppetlabs/server/data/postgresql/*', $destination_target)

  $pg_basebackup = @("PGBASE")
    runuser -u pe-postgres -- \
      /opt/puppetlabs/server/bin/pg_basebackup \
        -D /opt/puppetlabs/server/data/postgresql/11/data \
        -d "host=${source_host}
            user=pe-ha-replication
            sslmode=verify-full
            sslcert=/opt/puppetlabs/server/data/pg_certs/_local.cert.pem
            sslkey=/opt/puppetlabs/server/data/pg_certs/_local.private_key.pem
            sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem"
    | - PGBASE 

  run_command($pg_basebackup, $destination_target)

  run_command('rm -rf /opt/puppetlabs/server/data/pg_certs', $destination_target)

  # Start pe-postgresql.service
  run_command('systemctl start pe-postgresql.service', $destination_target)

  apply($source_target) {
    file_line { 'replication-pe-ha-replication-map':
      ensure => absent,
      path   => '/opt/puppetlabs/server/data/postgresql/11/data/pg_ident.conf',
      line   => "replication-pe-ha-replication-map ${destination_target.peadm::certname()} pe-ha-replication",
    }
    file_line { 'replication-pe-ha-replication-ipv4':
      ensure => absent,
      path   => '/opt/puppetlabs/server/data/postgresql/11/data/pg_hba.conf',
      line   => 'hostssl replication    pe-ha-replication 0.0.0.0/0  cert  map=replication-pe-ha-replication-map  clientcert=1',
    }
    file_line { 'replication-pe-ha-replication-ipv6':
      ensure => absent,
      path   => '/opt/puppetlabs/server/data/postgresql/11/data/pg_hba.conf',
      line   => 'hostssl replication    pe-ha-replication ::/0       cert  map=replication-pe-ha-replication-map  clientcert=1',
    }
  }

  # Reload pe-postgresql.service
  run_command('systemctl reload pe-postgresql.service', $source_target)

  return("The (re)population of ${$destination_target.peadm::certname()} with data from s${$source_target.peadm::certname()} succeeded.")

}
