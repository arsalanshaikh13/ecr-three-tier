const express = require("express");
const mysql = require("mysql2");
const bodyParser = require("body-parser");
const routes = require("./routes");
const cors = require("cors");
// const db = require('./configs/db'); // Import the db connection
const dbPromise = require("./configs/db");
const logger = require("./utils/logger"); // Import logger

const app = express();

app.use(cors());
app.use(bodyParser.json());

// db.connect((err) => {
//    if (err) {
//       logger.error(`Error connecting to MySQL: ${err.stack}`);
//       return;
//    }

//    logger.info('Connected to MySQL Database');
// });

// Initialize and start
(async () => {
  try {
    const db = await dbPromise;
    logger.info("Database connected");

    // // Make db available globally or pass it to routes
    // app.locals.db = db;
  } catch (err) {
    logger.error(`Failed to start: ${err.stack}`);
    process.exit(1);
  }
})();

/* Add your routes here */
//Health Checking
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "healthy",
    message: "Health check endpoint",
    timestamp: new Date().toISOString(),
  });
});

app.use("/api", routes);

module.exports = app;
