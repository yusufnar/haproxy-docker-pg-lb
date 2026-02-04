-- Database is created by environmental variables, using it directly
\c appdb;

-- Create table ynar
CREATE TABLE IF NOT EXISTS ynar (
    id SERIAL PRIMARY KEY,
    info TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NULL
);

-- Initial 10 records
INSERT INTO ynar (info) VALUES 
('Record 1'),
('Record 2'),
('Record 3'),
('Record 4'),
('Record 5'),
('Record 6'),
('Record 7'),
('Record 8'),
('Record 9'),
('Record 10');
