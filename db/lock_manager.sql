begin transaction;

create table lock (
	uuid TEXT PRIMARY KEY,
	expiry INT,
	owner TEXT,
	depth TEXT,
	scope TEXT
	path TEXT
);

commit;
