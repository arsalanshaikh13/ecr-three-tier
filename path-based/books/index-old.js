const express = require('express');
const path = require('path');
const data = require('./data');

const app = express();
const PORT = 3400;

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// CORS middleware. Can use npm package 'cors' as well.
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');

  if (req.method === 'OPTIONS') {
    res.sendStatus(200);
  } else {
    next();
  }
});

// Serve the main HTML file
app.get('/books', (req, res) => {
  res.sendFile(path.join(__dirname, 'views', 'index.html'));
});

// Health check endpoint
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok", message: "Service is healthy", uptime: process.uptime() });
});

// Books endpoint
app.get("/books/api", async (req, res) => {
  try {
    res.json({
      books: data.books
    });

  } catch (err) {
    console.error("Books fetch error:", err);
    res.status(500).json({ error: "Unable to fetch books" });
  }
});

app.listen(PORT, () => {
  console.log(`Server is running on http://localhost:${PORT}/books`);
});