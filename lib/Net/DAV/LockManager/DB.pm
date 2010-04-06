package Net::DAV::LockManager::DB;

use strict;

use DBI;
use Net::DAV::LockManager::UUID;

sub new {
	my ($class, $file) = @_;

	my $dsn = "dbi:SQLite:dbname=" . $file;

	return bless {
		"db" => DBI->connect($dsn, "", "")
	}, $class;
}

sub get {
	my ($self, $path) = @_;

	my $statement = $self->{"db"}->prepare("select * from lock where path = ?");
	$statement->execute($path);

	my $lock = $statement->fetchrow_hashref();

	$statement->finish();

	return $lock;
}

sub update {
	my ($self, $lock) = @_;

	my $statement = $self->{"db"}->prepare("update lock set expiry = ? where uuid = ?");

	$statement->execute(
		$lock->{"expiry"},
		$lock->{"uuid"}
	);

	return $lock;
}

sub add {
	my ($self, $lock) = @_;

	my $sql = qq{
		insert into lock (
			uuid, expiry, owner, depth, scope, path
		) values (
			?, ?, ?, ?, ?, ?
		)
	};

	$self->{"db"}->prepare($sql)->execute(
		Net::DAV::LockManager::UUID::generate(),
		$lock->{"expiry"},
		$lock->{"owner"},
		$lock->{"depth"},
		$lock->{"scope"},
		$lock->{"path"}
	);

	return $lock;
}

sub remove {
	my ($self, $lock) = @_;

	my $sql = qq{
		delete from lock where uuid = ?
	};

	$self->{"db"}->prepare($sql)->execute(
		$lock->{"uuid"}
	);
}

1;
