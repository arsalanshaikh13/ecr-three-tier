#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status

# echo "Starting seeder script..."

# # 1. Replace the placeholder with the actual DB Name from Environment Variables
# if [ -z "$DB_DATABASE" ]; then
#   echo "Error: DB_DATABASE environment variable is not set."
#   exit 1
# fi

# # sed -i "s/<react_node_app>/$DB_DATABASE/g" /scripts/db.sql
# sed -i "s/<react_node_app>/$DB_DATABASE/g" db.sql

# # 2. Wait for MySQL to be ready (RDS might be up, but network routing can take a second)
# echo "Waiting for host $DB_HOST to be reachable..."
# until mysqladmin ping -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" --silent; do
#   echo "Database is not ready yet... sleeping 2s"
#   sleep 2
# done

# # 3. Run the SQL script
# echo "Seeding database $DB_DATABASE..."
# # mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" < /scripts/db.sql
# mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" < db.sql

# echo "Database seeded successfully!"

# Removed 'set -e' so we can manually catch and log errors

echo "Starting seeder script..."

# 1. Check for DB_DATABASE
if [ -z "$DB_DATABASE" ]; then
  echo "[ERROR] DB_DATABASE environment variable is not set."
  exit 1
fi

echo "Replacing placeholder with $DB_DATABASE in SQL file..."
sed -i "s/<react_node_app>/$DB_DATABASE/g" db.sql

# 2. Wait for MySQL to be ready
echo "Waiting for host $DB_HOST to be reachable..."
until mysqladmin ping -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" --silent; do
  echo "Database is not ready yet... sleeping 2s"
  sleep 2
done

echo "Database connection established!"

# 3. Run the SQL script and capture the error code
echo "Seeding database $DB_DATABASE..."

# Run mysql and capture its exit code
if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" < db.sql; then
    echo "✅ Database seeded successfully!"
    exit 0
else
    # If mysql fails, it will print the SQL error to the console, 
    # and then we explicitly exit 1 so the ECS Waiter knows it failed.
    echo "❌ [ERROR] MySQL execution failed! Check the SQL syntax above."
    exit 1
fi