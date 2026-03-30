#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status

echo "Starting seeder script..."

# 1. Replace the placeholder with the actual DB Name from Environment Variables
if [ -z "$DB_NAME" ]; then
  echo "Error: DB_NAME environment variable is not set."
  exit 1
fi

sed -i "s/<react_node_app>/$DB_NAME/g" /scripts/db.sql

# 2. Wait for MySQL to be ready (RDS might be up, but network routing can take a second)
echo "Waiting for host $DB_HOST to be reachable..."
until mysqladmin ping -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" --silent; do
  echo "Database is not ready yet... sleeping 2s"
  sleep 2
done

# 3. Run the SQL script
echo "Seeding database $DB_NAME..."
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" < /scripts/db.sql

echo "Database seeded successfully!"