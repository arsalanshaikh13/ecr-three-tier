const dbConfigPromise = require("./DbConfig");
const mysql = require("mysql2");
require("dotenv").config();

// const host = process.env.DB_HOST || "localhost";
// const port = process.env.DB_PORT || "3306";
// const user = process.env.DB_USER || "root";
// const password = process.env.DB_PASSWORD || "12345678";
// const database = process.env.DB_NAME || "react_node_app";

let db;

// initialize connection asynchronously
const dbPromise = (async () => {
  try {
    const dbcreds = await dbConfigPromise;

    db = mysql.createConnection({
      host: dbcreds.DB_HOST,
      user: dbcreds.DB_USER,
      password: dbcreds.DB_PASSWORD,
      database: dbcreds.DB_DATABASE,
      port: dbcreds.DB_PORT,
      // port: "3306",
    });

    //   db.connect((err) => {
    //     if (err) {
    //       console.error("❌ Database connection failed:", err);
    //       process.exit(1);
    //     }
    //     console.log("✅ Connected to database!");
    //   });
    // } catch (err) {
    //   console.error("❌ Failed to load DB config:", err);
    //   process.exit(1);
    // }
    await new Promise((resolve, reject) => {
      db.connect((err) => {
        if (err) {
          console.error("❌ Database connection failed:", err);
          reject(err);
        } else {
          console.log("✅ Connected to database!");
          resolve();
        }
      });
    });

    return db;
  } catch (err) {
    console.error("❌ Failed to load DB config:", err);
    throw err;
  }
})();

// const db = mysql.createConnection({
//   host: host,
//   port: port,
//   user: user,
//   password: password,
//   database: database,
// });

// module.exports = db;
module.exports = dbPromise;
