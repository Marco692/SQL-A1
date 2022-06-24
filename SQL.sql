CREATE TABLE Person(
	PID INTEGER,
	email VARCHAR(30) NOT NULL,
	name VARCHAR(20) NOT NULL, --name belongs to "non-reserved" key words in PostgreSQL, which can be used as column or table names.
	gender VARCHAR(10) NOT NULL CHECK (gender IN('male','female')),
	birth_country VARCHAR(20) NOT NULL,
	home_country VARCHAR(20) NOT NULL,
	date_of_birth DATE NOT NULL,
	job VARCHAR(10) NOT NULL CHECK (job IN('athlete','official')), --In order to achieve disjoint and total constarints.(cooperate with trigger and trigger function latter)
	PRIMARY KEY(PID),
	UNIQUE(email)
);

--The age belongs to derived attribute, but Postgres only supports STORED generated columns
--Therefore, create a view to get the functionality of VIRTUAL generated columns 
CREATE VIEW Person_Age AS(
	SELECT PID, name, age(date_of_birth) age
	FROM Person
);

CREATE TABLE Athletes(
	PID INTEGER,
	PRIMARY KEY(PID),
	FOREIGN KEY (PID) REFERENCES Person ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Officials(
	PID INTEGER,
	PRIMARY KEY(PID),
	FOREIGN KEY (PID) REFERENCES Person ON DELETE CASCADE ON UPDATE CASCADE
);
-------------------------------------------------------------------------------------------------------- 

CREATE TABLE Events(
	event_name VARCHAR(90),
	result_type VARCHAR(5) NOT NULL CHECK(result_type IN('time','score')),
	sport_category VARCHAR(20) NOT NULL,
	event_date DATE NOT NULL CHECK (event_date > '2024-01-01' and event_date < '2024-12-31'),
	event_time TIME NOT NULL,
	PRIMARY KEY(event_name)
);

CREATE TABLE Participate(
	PID INTEGER,
	event_name VARCHAR(90),
	result VARCHAR(30) NOT NULL,
	PRIMARY KEY(PID, event_name),
	FOREIGN KEY (PID) REFERENCES Athletes ON DELETE CASCADE ON UPDATE CASCADE,
	FOREIGN KEY (event_name) REFERENCES Events ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Run(
	PID INTEGER,
	event_name VARCHAR(90),
	work_types VARCHAR(20) NOT NULL CHECK(work_types IN ('referee games','judge performance','award medals')),
	PRIMARY KEY(PID, event_name, work_types),--one official can play many roles at one event
	FOREIGN KEY (PID) REFERENCES Officials ON DELETE CASCADE ON UPDATE CASCADE,
	FOREIGN KEY (event_name) REFERENCES Events ON DELETE CASCADE ON UPDATE CASCADE
);
-------------------------------------------------------------------------------------------------------- 

CREATE TABLE Location(  --location belongs to "non-reserved" key words in PostgreSQL, which can be used as column or table names.
	location_name VARCHAR(30),
	build_date DATE NOT NULL,
	build_cost INTEGER NOT NULL CHECK(build_cost>0),
	address VARCHAR(50) NOT NULL,
	longitude DECIMAL(10,6) NOT NULL,
	latitude DECIMAL(10,6) NOT NULL,
	location_type VARCHAR(10) NOT NULL CHECK (location_type IN('venue','village')), --In order to achieve disjoint and total constarints.(cooperate with trigger and trigger function latter)
	PRIMARY KEY(location_name)
);

CREATE TABLE Venues(
	location_name VARCHAR(30) PRIMARY KEY,
	FOREIGN KEY (location_name) REFERENCES Location ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Villages(
	location_name VARCHAR(30) PRIMARY KEY,
	FOREIGN KEY (location_name) REFERENCES Location ON DELETE CASCADE ON UPDATE CASCADE
);

ALTER TABLE Person --describe the person stay at which village（represent the StayAt relationship）
ADD COLUMN village_name VARCHAR(30) NOT NULL,
ADD CONSTRAINT Person_village_name_fk FOREIGN KEY(village_name) REFERENCES Villages ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE Events  --describe the event is held at which venue（represent the Host relationship）
ADD COLUMN venues_name VARCHAR(30) NOT NULL,
ADD CONSTRAINT Events_venues_name_fk FOREIGN KEY(venues_name) REFERENCES Venues ON DELETE SET NULL ON UPDATE CASCADE;
-------------------------------------------------------------------------------------------------------- 

CREATE TABLE Vehicles(
	vehicle_code VARCHAR(10),
	vehicle_type VARCHAR(7) NOT NULL CHECK(vehicle_type IN ('van','minibus','bus')),
	capacity INTEGER NOT NULL CHECK(capacity>0 AND capacity<=23),
	PRIMARY KEY(vehicle_code)
);

CREATE EXTENSION btree_gist; --to define exclusion constraints
CREATE TABLE Schedule( --weak enetity
	SID INTEGER,
	vehicle_code VARCHAR(10),
	starting VARCHAR(30) NOT NULL,
	destination VARCHAR(30) NOT NULL,
	starting_time TIMESTAMP  NOT NULL,
	destination_time TIMESTAMP  NOT NULL,
	PRIMARY KEY(SID,vehicle_code),
	FOREIGN KEY(vehicle_code) REFERENCES Vehicles ON DELETE CASCADE ON UPDATE CASCADE,
	FOREIGN KEY(starting) REFERENCES Location ON DELETE CASCADE ON UPDATE CASCADE,
	FOREIGN KEY(destination) REFERENCES Location ON DELETE CASCADE ON UPDATE CASCADE,
	CHECK(starting <> destination),
	CHECK(starting_time< destination_time),
	EXCLUDE USING GIST (vehicle_code WITH =, tsrange(starting_time, destination_time) WITH &&)
	--avoid overlapping time in the same vehicle 
);

CREATE TABLE Book(
	PID INTEGER,
	SID INTEGER,
	vehicle_code VARCHAR(10),
	PRIMARY KEY(PID,SID,vehicle_code),
	FOREIGN KEY(PID) REFERENCES Person ON DELETE CASCADE ON UPDATE CASCADE,
	FOREIGN KEY(SID,vehicle_code) REFERENCES Schedule ON DELETE CASCADE ON UPDATE CASCADE
);
-------------------------------------------------------------------------------------------------------- 

--create trriger function to identify what kinds of the person is
--and send its PID to coresponding table
CREATE OR REPLACE FUNCTION identify_person() RETURNS trigger AS $$
BEGIN
IF NEW.job = 'athlete' then
	INSERT INTO Athletes VALUES(NEW.PID);
ELSE
	INSERT INTO Officials VALUES(NEW.PID);        
END IF;
RETURN NEW;
END;$$
LANGUAGE plpgsql;
--create trriger--
CREATE TRIGGER person_identification  
	AFTER INSERT ON person 
	FOR EACH ROW
	EXECUTE PROCEDURE identify_person();
	
--similar to the above trriger, identify what kinds of the location is
--and send its location_name to coresponding table
CREATE OR REPLACE FUNCTION identify_location() RETURNS trigger AS $$
BEGIN
IF NEW.location_type = 'venue' then
	INSERT INTO Venues VALUES(NEW.location_name);
ELSE
	INSERT INTO Villages VALUES(NEW.location_name);        
END IF;
RETURN NEW;
END;$$
LANGUAGE plpgsql;
--create trriger--
CREATE TRIGGER location_identification  
	AFTER INSERT ON location 
	FOR EACH ROW
	EXECUTE PROCEDURE identify_location();

--Each type of vehicle has a fixed maximun capacity,
--If the input value is larger than maximun, automatically reset it to maximun
--If the input value is smaller than maximun (in some specical case, seats are broken), keep the smaller value instead of default maximun values
CREATE OR REPLACE FUNCTION add_capacity() RETURNS trigger AS $$
BEGIN
IF (NEW.Vehicle_type = 'van' AND NEW.capacity>7) THEN --set the maximum capacity of van is 7
		UPDATE Vehicles SET capacity =7
		WHERE vehicle_code =NEW.vehicle_code;
END IF;

IF (NEW.Vehicle_type = 'minibus' AND NEW.capacity>14) THEN --set the maximum capacity of minibus is 14
		UPDATE Vehicles SET capacity =14
		WHERE vehicle_code =NEW.vehicle_code;
END IF;

IF (NEW.Vehicle_type = 'bus' AND NEW.capacity>23) THEN --set the maximum capacity of bus is 23
		UPDATE Vehicles SET capacity =23
		WHERE vehicle_code =NEW.vehicle_code;
END IF;

RETURN NEW;
END;$$
LANGUAGE plpgsql;
--create trriger--
CREATE TRIGGER vehicel_capacity  
	AFTER INSERT ON Vehicles
	FOR EACH ROW
	EXECUTE PROCEDURE add_capacity();
-------------------------------------------------------------------------------------------------------- 

--add some examples into supertype(Location table). These examples are added into subtypes(Venues table&Villages table) automatically. 
INSERT INTO Location VALUES ('ABC_sport', '2020-10-02', 50000000,'5 Avernue', 125.777777,10.111111111, 'venue');
INSERT INTO Location VALUES ('EDF_sport', '2021-10-03', 40000000,'4 avernue', 133.1111111,20.111111111, 'venue');
INSERT INTO Location VALUES ('QWE_accommodation', '2022-10-04', 30000000,'3 avernue', 144.1111111,21.111111111, 'village');
INSERT INTO Location VALUES ('ASD_accommodation', '2023-10-05', 20000000,'2 avernue', 110.1111111,25.111111111, 'village');

--add some examples into supertype(Person table). These examples are added into subtypes(Athletes table&Officials table) automatically.
--The examples includ additional attribute(villages_name) stemed from StayAt relationship.
INSERT INTO Person VALUES ('123456', 'abc@google.com', 'Marco','male', 'China','USA','1997-10-09', 'athlete','QWE_accommodation');
INSERT INTO Person VALUES ('234567', 'def@google.com', 'Regin','female', 'China','AUS','1998-04-23', 'official','QWE_accommodation');
INSERT INTO Person VALUES ('345678', 'ghi@google.com', 'Revel','male', 'India','USA','1997-07-12','athlete','ASD_accommodation');
INSERT INTO Person VALUES ('456789', 'jkl@google.com', 'Elian','female', 'India','USA','1997-03-27', 'official','ASD_accommodation');

--add some examples into Events table. The examples includ additional attribute(venues_name) stemed from Host relationship.
INSERT INTO Events VALUES ('Men''s Table Tennis Singles final', 'score', 'Table Tennis','2024-10-08', '17:30:00','ABC_sport');
INSERT INTO Events VALUES ('Women''s Table Tennis Singles final', 'score', 'Table Tennis','2024-10-09', '17:30:00','ABC_sport');
INSERT INTO Events VALUES ('Men''s 100m final', 'time', 'Athletics','2024-10-12', '17:30:00','EDF_sport');
INSERT INTO Events VALUES ('Women''s 100m final', 'time', 'Athletics','2024-10-13', '17:30:00','EDF_sport');

--add some examples into Participate table.
INSERT INTO Participate VALUES ('123456','Men''s 100m final', '9.85');
INSERT INTO Participate VALUES ('345678','Men''s Table Tennis Singles final', '11,7,11,11');

--add some examples into Run table.
INSERT INTO Run VALUES ('234567','Men''s 100m final', 'referee games');
INSERT INTO Run VALUES ('234567','Men''s 100m final', 'award medals');
INSERT INTO Run VALUES ('456789','Men''s Table Tennis Singles final', 'judge performance');
INSERT INTO Run VALUES ('456789','Men''s Table Tennis Singles final', 'award medals');

--add some examples into Vehicles table. The values of capacity wiil be check by semantic constraint and trigger function.
INSERT INTO Vehicles VALUES ('V001','van',7);
INSERT INTO Vehicles VALUES ('V002','van',5);
INSERT INTO Vehicles VALUES ('V003','van',8);
INSERT INTO Vehicles VALUES ('M003','minibus',14);
INSERT INTO Vehicles VALUES ('B003','bus',23);

--add some examples into Schedule table.
INSERT INTO Schedule VALUES ('0001','V001','ABC_sport','QWE_accommodation','2021-10-4 21:00:00','2021-10-4 21:30:00');
--INSERT INTO schedule VALUES ('0005','V001','EDF_sport','ASD_accommodation','2021-10-4 21:10:00','2021-10-4 21:20:00');
--Compared with example1, this example has same vehicle_code and overlapping duration
INSERT INTO Schedule VALUES ('0002','V001','QWE_accommodation','ABC_sport','2021-10-4 21:35:00','2021-10-4 22:05:00');
INSERT INTO Schedule VALUES ('0003','M003','EDF_sport','ABC_sport','2021-10-4 15:35:00','2021-10-4 16:00:00');
INSERT INTO Schedule VALUES ('0004','B003','EDF_sport','QWE_accommodation','2021-10-5 15:35:00','2021-10-5 16:35:00');

--add some examples into Book table.
INSERT INTO Book VALUES('123456','0002','V001');
INSERT INTO Book VALUES('234567','0002','V001');
INSERT INTO Book VALUES('234567','0004','B003');
INSERT INTO Book VALUES('456789','0004','B003');