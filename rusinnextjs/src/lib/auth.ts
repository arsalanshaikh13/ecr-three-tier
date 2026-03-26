import { betterAuth } from "better-auth";
import { MongoClient } from "mongodb";
import { mongodbAdapter } from "better-auth/adapters/mongodb";
import jwt from "jsonwebtoken";

// 1. Fallback to dummy so it doesn't throw if undefined
const uri = process.env.MONGODB_URI || "mongodb://build-time-dummy";
const isBuildTime = uri.includes("build-time-dummy");

const client = new MongoClient(uri);

let clientPromise: Promise<MongoClient>;

// 2. The Build-Time Bypass
if (!isBuildTime) {
  // Normal Runtime: Actually connect to the database
  if (!(global as any)._mongoClientPromise) {
    (global as any)._mongoClientPromise = client.connect();
  }
  clientPromise = (global as any)._mongoClientPromise;
} else {
  // Build Time: Instantly resolve with an unconnected client
  console.warn(
    "⚠️ Build time detected in Auth. Skipping MongoClient.connect().",
  );
  clientPromise = Promise.resolve(client);
}

export async function getDb() {
  const resolvedClient = await clientPromise;
  // This works synchronously and safely without network calls
  return resolvedClient.db();
}

export const auth = betterAuth({
  database: mongodbAdapter(await getDb(), {}),
  trustedHosts: ["*"],

  user: {
    additionalFields: {
      sub: { type: "string", required: true },
      username: { type: "string", required: true },
      role: { type: "string" },
      permissions: { type: "string" },
      identities: { type: "string" },
    },
  },

  socialProviders: {
    cognito: {
      // 3. Optional safety fallback for string parsing during build
      clientId: process.env.COGNITO_CLIENT_ID || "dummy-client-id",
      clientSecret: process.env.COGNITO_CLIENT_SECRET || "dummy-client-secret",
      domain: process.env.COGNITO_DOMAIN || "dummy-domain",
      region: process.env.COGNITO_REGION || "dummy-region",
      userPoolId: process.env.COGNITO_USER_POOL_ID || "dummy-user-pool-id",
      scope: ["email", "openid", "profile", "aws.cognito.signin.user.admin"],

      getUserInfo: async (token) => {
        const userInfoResponse = await fetch(
          `https://${process.env.COGNITO_DOMAIN}/oauth2/userInfo`,
          {
            headers: {
              Authorization: `Bearer ${token.accessToken}`,
            },
          },
        );

        if (!userInfoResponse.ok) {
          throw new Error("Failed to fetch user info from Cognito");
        }

        const userInfo = await userInfoResponse.json();

        const decoded = jwt.decode(token.accessToken as string) as Record<
          string,
          string | number
        >;

        return {
          user: {
            id: userInfo.sub,
            sub: userInfo.sub,
            username: userInfo.username || "",
            name: userInfo.name,
            email: userInfo.email,
            emailVerified: userInfo.email_verified === "true" || false,
            role: userInfo["custom:role"] || "user",
            permissions: decoded?.scope || "",
            identities: userInfo.identities || "",
          },
          data: userInfo,
        };
      },
    },
  },
});
