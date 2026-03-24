const express = require('express');
const path = require('path');

const app = express();
const PORT = 3200;

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Serve the main HTML file
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'views', 'index.html'));
});

// Health check endpoint
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok", message: "Service is healthy", uptime: process.uptime() });
});

// Config endpoint
app.get('/config', (req, res) => {
  res.status(200).json({
    BOOKS_SERVICE_URL: process.env.BOOKS_SERVICE_URL || 'http://localhost:3400/books',
    AUTHORS_SERVICE_URL: process.env.AUTHORS_SERVICE_URL || 'http://localhost:3300/authors'
  });
});

app.listen(PORT, () => {
  console.log(`Server is running on http://localhost:${PORT}`);
});