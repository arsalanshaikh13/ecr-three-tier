import { headers } from "next/headers";
import { NextRequest, NextResponse } from "next/server";
import { auth } from "./lib/auth";

export async function proxy(request: NextRequest) {
  const pathname = request.nextUrl.pathname;

  // Routes that require authentication
  const protectedRoutes = ["/dashboard", "/tasks"];

  // Check if current route is protected
  const isProtectedRoute = protectedRoutes.some((route) =>
    pathname.startsWith(route),
  );

  const headersList = await headers();
  const session = await auth.api.getSession({
    headers: headersList,
  });

  const user = session?.user || null;

  if (isProtectedRoute) {
    // If no session exists, redirect to home page
    if (!user) {
      return NextResponse.redirect(new URL("/", request.url));
    }
  }

  // If user is logged in and trying to access home page, redirect to dashboard
  if (pathname === "/") {
    if (user) {
      return NextResponse.redirect(new URL("/dashboard", request.url));
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    "/",
    "/dashboard",
    "/dashboard/:path*",
    "/tasks",
    "/tasks/:path*",
    "/settings",
    "/settings/:path*",
  ],
};

// import { NextRequest, NextResponse } from "next/server";

// export async function proxy(request: NextRequest) {
//   const pathname = request.nextUrl.pathname;

//   const protectedRoutes = ["/dashboard", "/tasks", "/settings"];
//   const isProtectedRoute = protectedRoutes.some((route) =>
//     pathname.startsWith(route),
//   );

//   // --- THE FIX ---
//   // // // Force the fetch to use the internal, unencrypted HTTP port of the container
//   // // const sessionUrl = "http://localhost:3000/api/auth/get-session";
//   // // We use the actual host header (devsandbox.space) but force HTTP.
//   // // Next.js intercepts this internally, skipping OpenSSL crashes and bypassing localhost drops.
//   // const host = request.headers.get("host") || "localhost:3000";
//   // const sessionUrl = `http://${host}/api/auth/get-session`;

//   // / Hardcode the public URL. This forces the request through your AWS Load Balancer,
//   // bypassing all Docker internal loopback restrictions and SSL bugs.
//   const sessionUrl = "https://devsandbox.space/api/auth/get-session";
//   // ---------------

//   try {
//     const response = await fetch(sessionUrl, {
//       headers: {
//         cookie: request.headers.get("cookie") || "",
//         "x-forwarded-proto":
//           request.headers.get("x-forwarded-proto") || "https",
//         // This tricks Better Auth into thinking this internal fetch came from the public internet
//         host: request.headers.get("host") || "devsandbox.space",
//         origin: "https://devsandbox.space",
//       },
//     });

//     const session = response.ok ? await response.json() : null;
//     const user = session?.user || null;

//     if (isProtectedRoute && !user) {
//       return NextResponse.redirect(new URL("/", request.url));
//     }

//     if (pathname === "/" && user) {
//       return NextResponse.redirect(new URL("/dashboard", request.url));
//     }
//   } catch (error) {
//     // Failsafe: If the internal fetch ever fails, don't crash the app (500),
//     // just assume they aren't logged in and let them proceed to the public page.
//     console.error("Middleware session fetch failed:", error);
//     if (isProtectedRoute) {
//       return NextResponse.redirect(new URL("/", request.url));
//     }
//   }

//   return NextResponse.next();
// }

// export const config = {
//   matcher: [
//     "/",
//     "/dashboard",
//     "/dashboard/:path*",
//     "/tasks",
//     "/tasks/:path*",
//     "/settings",
//     "/settings/:path*",
//   ],
// };
