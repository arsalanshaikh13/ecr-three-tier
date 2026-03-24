const express = require("express");
const path = require("path");
const helmet = require("helmet");
const morgan = require("morgan");
const cors = require("cors");
const data = require("./data");

const app = express();
const PORT = process.env.PORT || 3400;

// --- Middlewares ---
// Security headers to protect against common web vulnerabilities
app.use(helmet({ contentSecurityPolicy: false }));
// Request logging for observability (routes to CloudWatch in ECS)
app.use(morgan("combined"));
// Standardized CORS implementation
app.use(cors());

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// --- Routes ---
// Serve the main HTML file
app.get("/books", (req, res) => {
  res.sendFile(path.join(__dirname, "views", "index.html"));
});

// Health check endpoint (Essential for ALB Target Groups)
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "ok",
    message: "Books service is healthy",
    uptime: process.uptime(),
  });
});

// Books API endpoint
app.get("/books/api", async (req, res) => {
  try {
    res.json({
      books: data.books,
    });
  } catch (err) {
    console.error("Books fetch error:", err);
    res.status(500).json({ error: "Unable to fetch books" });
  }
});

// Global error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: "Internal Server Error in Books Service" });
});

// --- Server Initialization ---
const server = app.listen(PORT, () => {
  console.log(`Books service is running on port ${PORT}`);
});

// --- Graceful Shutdown (Critical for ECS Task Cycling) ---
process.on("SIGTERM", () => {
  console.info(
    "SIGTERM signal received: Closing Books HTTP server to drain inflight requests.",
  );
  server.close(() => {
    console.info("Books HTTP server closed.");
    process.exit(0);
  });
});

process.on("SIGINT", () => {
  console.info("SIGINT signal received: Shutting down locally.");
  server.close(() => {
    process.exit(0);
  });
});
