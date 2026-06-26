USE mm_license;

-- Achtung: Demo-Daten. API-Key-Hash muss in der echten Implementierung
-- mit dem gewählten Hash-Verfahren erzeugt werden.
INSERT INTO customers (customer_uid, external_customer_ref, name, email)
VALUES ('cust_demo', 'demo-kunde', 'Demo Kunde GmbH', 'demo@example.invalid')
ON DUPLICATE KEY UPDATE name = VALUES(name);

INSERT INTO projects (project_uid, project_key, name, php_min_version)
VALUES ('proj_mangelmelder', 'mangelmelder', 'Mangelmelder', '8.4')
ON DUPLICATE KEY UPDATE name = VALUES(name);
