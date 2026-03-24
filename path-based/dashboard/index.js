const express = require("express");
const path = require("path");
const helmet = require("helmet");
const morgan = require("morgan");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 3200;

// --- Middlewares ---
// Security headers. (Note: contentSecurityPolicy is disabled here for simplicity with inline scripts in index.html,
// but in a strict production environment, you should extract inline scripts and enable CSP).
app.use(helmet({ contentSecurityPolicy: false }));
// Request logging for CloudWatch
app.use(morgan("combined"));
// Enable CORS if your services are on different subdomains (Host-based routing)
app.use(cors());

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// --- Routes ---
app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "views", "index.html"));
});

// Health check endpoint (Crucial for ALB target group health checks)
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "ok",
    message: "Service is healthy",
    uptime: process.uptime(),
  });
});

// Config endpoint
// PRO TIP FOR ECS: If using Path-Based routing on the same domain (e.g., api.yourdomain.com/books),
// your ENV vars in ECS should just be "/books" and "/authors" to avoid CORS entirely.
app.get("/config", (req, res) => {
  res.status(200).json({
    BOOKS_SERVICE_URL:
      process.env.BOOKS_SERVICE_URL || "http://localhost:3400/books",
    AUTHORS_SERVICE_URL:
      process.env.AUTHORS_SERVICE_URL || "http://localhost:3300/authors",
  });
});

// Global error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: "Something broke internally!" });
});

const server = app.listen(PORT, () => {
  console.log(`Dashboard server is running on port ${PORT}`);
});

// --- Graceful Shutdown (Essential for ECS) ---
process.on("SIGTERM", () => {
  console.info(
    "SIGTERM signal received: Closing HTTP server to drain inflight requests.",
  );
  server.close(() => {
    console.info("HTTP server closed.");
    process.exit(0);
  });
});

process.on("SIGINT", () => {
  console.info("SIGINT signal received: Shutting down locally.");
  server.close(() => {
    process.exit(0);
  });
});
