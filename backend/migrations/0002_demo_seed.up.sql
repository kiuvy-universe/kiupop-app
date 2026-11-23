-- Fictitious demo data. Prices are integer minor units (CRC céntimos).
INSERT INTO demo_products (id, name, description, price_minor, currency, sort_order) VALUES
    ('demo-cafe',    'Café de altura 340 g',  'Producto ficticio de demostración.', 450000, 'CRC', 1),
    ('demo-pan',     'Pan casero',            'Producto ficticio de demostración.', 150000, 'CRC', 2),
    ('demo-tote',    'Bolso de tela',         'Producto ficticio de demostración.', 800000, 'CRC', 3)
ON CONFLICT (id) DO NOTHING;
