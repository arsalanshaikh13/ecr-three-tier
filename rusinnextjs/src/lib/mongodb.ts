import mongoose from "mongoose";

const MONGODB_URI = process.env.MONGODB_URI;

interface CachedConnection {
  conn: typeof mongoose | null;
  promise: Promise<typeof mongoose> | null;
}

// Declare global mongoose cache for Next.js hot-reloading
declare global {
  var mongooseCache: CachedConnection;
}

let cached: CachedConnection = global.mongooseCache;

if (!cached) {
  cached = global.mongooseCache = { conn: null, promise: null };
}

/**
 * Connect to MongoDB
 * Uses caching to avoid multiple connections in development (Turbopack reloads)
 */
export async function connectToDatabase() {
  // ---------------------------------------------------------
  // 1. CI/CD BUILD-TIME BYPASS
  // Intercept the dummy URI from GitHub Actions so it doesn't try to connect
  // ---------------------------------------------------------
  if (MONGODB_URI === "mongodb://build-time-dummy") {
    console.warn("⚠️ Build time detected. Skipping actual MongoDB connection.");
    // We return the unconnected mongoose object just to satisfy TypeScript
    // and any auth libraries that expect a defined return value.
    return mongoose;
  }

  // ---------------------------------------------------------
  // 2. RUNTIME MISSING VAR CHECK
  // Moved inside the function so it doesn't crash the build stage
  // ---------------------------------------------------------
  if (!MONGODB_URI) {
    throw new Error(
      "❌ Please define the MONGODB_URI environment variable inside ECS or .env.local",
    );
  }

  // ---------------------------------------------------------
  // 3. STANDARD CONNECTION LOGIC
  // ---------------------------------------------------------
  if (cached.conn) {
    return cached.conn;
  }

  if (!cached.promise) {
    const opts = {
      bufferCommands: false,
    };

    cached.promise = mongoose
      .connect(MONGODB_URI as string, opts)
      .then((mongoose) => {
        console.log("✅ Connected to MongoDB");
        return mongoose;
      })
      .catch((error) => {
        console.error("❌ MongoDB connection error:", error);
        throw error;
      });
  }

  try {
    cached.conn = await cached.promise;
  } catch (e) {
    cached.promise = null;
    throw e;
  }

  return cached.conn;
}

export default connectToDatabase;
