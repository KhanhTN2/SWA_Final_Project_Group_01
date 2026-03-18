INSERT INTO products (product_number, name) VALUES
    ('PROD001', 'Laptop'),
    ('PROD002', 'Mouse'),
    ('PROD003', 'Keyboard'),
    ('PROD004', 'Monitor'),
    ('PROD005', 'Headphones')
ON CONFLICT (product_number) DO NOTHING;
