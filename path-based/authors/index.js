const express = require("express");
const path = require("path");
const helmet = require("helmet");
const morgan = require("morgan");
const cors = require("cors");
const data = require("./data");

const app = express();
const PORT = process.env.PORT || 3300;

// --- Middlewares ---
// Security headers
app.use(helmet({ contentSecurityPolicy: false }));
// HTTP request logging (essential for CloudWatch logs)
app.use(morgan("combined"));
// Replaced your manual CORS setup with the standard, robust npm package
app.use(cors());

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// --- Routes ---
// Serve the main HTML file
app.get("/authors", (req, res) => {
  res.sendFile(path.join(__dirname, "views", "index.html"));
});

// Health check endpoint (Configure your ALB Target Group to ping this)
app.get("/health", (req, res) => {
  res
    .status(200)
    .json({
      status: "ok",
      message: "Authors service is healthy",
      uptime: process.uptime(),
    });
});

// Authors endpoint
app.get("/authors/api", async (req, res) => {
  try {
    // Simulated delay or actual DB call could go here in the future
    res.json({
      authors: data.authors,
    });
  } catch (err) {
    // Fixed the copy-paste bug here (was "Books fetch error")
    console.error("Authors fetch error:", err);
    res.status(500).json({ error: "Unable to fetch authors" });
  }
});

// Global error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: "Internal Server Error in Authors Service" });
});

// --- Server Initialization ---
const server = app.listen(PORT, () => {
  console.log(`Authors service is running on port ${PORT}`);
});

// --- Graceful Shutdown (Critical for ECS Task Termination) ---
process.on("SIGTERM", () => {
  console.info(
    "SIGTERM signal received: Closing Authors HTTP server to drain inflight requests.",
  );
  server.close(() => {
    console.info("Authors HTTP server closed.");
    process.exit(0);
  });
});

process.on("SIGINT", () => {
  console.info("SIGINT signal received: Shutting down locally.");
  server.close(() => {
    process.exit(0);
  });
});
