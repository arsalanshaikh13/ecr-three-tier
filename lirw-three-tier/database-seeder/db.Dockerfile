# Use the official MySQL 8 image which contains the 'mysql' client
FROM mysql:8

# Create a directory for our SQL scripts
WORKDIR /scripts

# Copy  schema/data file into the container
# Copy both the SQL and the shell script
COPY db.sql /scripts/db.sql
COPY script.sh /scripts/script.sh

# Give execution permission to the script
RUN chmod +x /scripts/script.sh


# Use a shell script as the CMD to allow for better error logging
# ECS will inject DB_HOST, DB_USER, and DB_PASSWORD as Env Vars
# CMD ["sh", "-c", "mysql -h \"$DB_HOST\" -u \"$DB_USER\" -p\"$DB_PASSWORD\" < /scripts/db.sql && echo 'Database seeded successfully'"]
# Run the script
CMD ["/scripts/script.sh"]