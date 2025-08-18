-- Grant permissions for postal user to create and manage postal-* databases
GRANT ALL PRIVILEGES ON `postal-%`.* TO 'postal'@'%';
FLUSH PRIVILEGES;