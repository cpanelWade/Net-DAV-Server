package Net::DAV::LockManager::DB;

use strict;

use DBI;
use File::Temp qw(tmpnam);

our @schema = (
	qq{
		create table lock (
			uuid CHAR(36) PRIMARY KEY,
			expiry INTEGER,
			owner CHAR(128),
			depth CHAR(32),
			scope CHAR(32),
			path CHAR(512) 
		)
	}
);

#
# Create a new lock manager database context.  Optionally accepts a
# parameter representing a DBI-formatted Data Source Name (DSN).  If no
# DSN is provided, then a temporary SQLite database is used by default.
#
sub new {
	my $class = shift;
	my $dsn = $_[0]? $_[0]: undef;
	my $tmp = undef;

	unless ($dsn) {
		$dsn = sprintf("dbi:SQLite:dbname=%s", $tmp = File::Temp::tmpnam("/tmp", ".webdav-locks"));
	}

	my $self = bless {
		"db" => DBI->connect($dsn, "", "")
	}, $class;

	#
	# In the event no file name was passed, take note of this fact in the
	# new object instance so that a proper cleanup can happen at destruction
	# time.
	#
	if ($tmp) {
		$self->{"tmp"} = $tmp;
	}

	#
	# Perform any database initializations that may be required prior to
	# returning the newly-constructed object.
	#
	$self->_initialize();

	return $self;
}

#
# Called from the constructor to initialize state (including database
# file and schema) prior to returning a newly-instantiated object.
#
sub _initialize {
	my ($self) = @_;

	#
	# Enable transactions for the duration of this method.  Enable
	# error reporting.
	#
	$self->{"db"}->{"AutoCommit"} = 0;
	$self->{"db"}->{"RaiseError"} = 1;

	#
	# Only perform initialization if the table definition is missing.
	# We can use the internal SQLite table SQLITE_MASTER to verify
	# the presence of our lock table.
	#
	# If the schema has already been applied to the current database,
	# then we can safely return.
	#
	if ($self->{"db"}->selectrow_hashref("select name from sqlite_master where name = 'lock'")) {
		return;
	}

	#
	# The schema has not been applied.  Instantiate it.
	#
	eval {
		foreach my $definition (@schema) {
			$self->{"db"}->do($definition);
		}
	};

	#
	# Gracefully recover from any errors in instantiating the schema,
	# in this case by throwing another error describing the situation.
	#
	if ($@) {
		warn("Unable to initialize database schema: $@");

		eval {
			$self->{"db"}->rollback();
		};
	}

	#
	# Disable transactions again.  This is fine, as transactions are
	# disabled by default when creating a new DBI context.
	#
	$self->{"db"}->{"AutoCommit"} = 1;
}

#
# Intended to be dispatched by the caller whenever the database is no
# longer required.  This method will remove any temporary, one-time
# use databases which may have been created at object instantiation
# time.
#
sub close {
	my ($self) = @_;

	$self->{"db"}->disconnect();

	#
	# If the name of a temporary database was stored in this object,
	# be sure to unlink() said file.
	#
	if ($self->{"tmp"}) {
		unlink($self->{"tmp"});
	}
}

#
# Garbage collection hook to perform tidy cleanup prior to deallocation.
#
sub DESTROY {
	my ($self) = @_;

	$self->close();
}

#
# Given a normalized string representation of a resource path, return
# the first lock found.
#
sub get {
	my ($self, $path) = @_;

	return $self->{"db"}->selectrow_hashref("select * from lock where path = ?", {}, $path);
}

#
# Given a hash reference containing a lock, update any locks
# corresponding to the path therein with the expiry and UUID
# as listed in the record.
#
sub update {
	my ($self, $lock) = @_;

	my $statement = $self->{"db"}->prepare("update lock set expiry = ? where path = ?");

	$statement->execute(
		$lock->{"expiry"},
		$lock->{"path"}
	);

	return $lock;
}

#
# When provided a hash reference containing the following pieces
# of information (per hash element) will be inserted into the database:
#
# * UUID
# * expiry
# * owner
# * depth
# * scope
# * path
#
sub add {
	my ($self, $lock) = @_;

	my $sql = qq{
		insert into lock (
			uuid, expiry, owner, depth, scope, path
		) values (
			?, ?, ?, ?, ?, ?
		)
	};

	$self->{"db"}->do($sql, {},
		$lock->{"uuid"},
		$lock->{"expiry"},
		$lock->{"owner"},
		$lock->{"depth"},
		$lock->{"scope"},
		$lock->{"path"}
	);

	return $lock;
}

#
# Given a lock, the database record which contains the corresponding
# path will be removed.  The UUID in the lock passed will be overwritten
# with an undef value to force invalidation of the lock.
#
sub remove {
	my ($self, $lock) = @_;

	$self->{"db"}->do("delete from lock where path = ?", {}, $lock->{"path"});

	$lock->{"uuid"} = undef;
}

1;
