// import { NextRequest, NextResponse } from "next/server";

// export async function middleware(request: NextRequest) {
//   const pathname = request.nextUrl.pathname;

//   // Routes that require authentication
//   const protectedRoutes = ["/dashboard", "/tasks", "/settings"];

//   // Check if current route is protected
//   const isProtectedRoute = protectedRoutes.some((route) =>
//     pathname.startsWith(route)
//   );

//   // 1. THE EDGE-SAFE SESSION FETCH
//   // We ping the Better Auth endpoint internally instead of importing the MongoDB auth library
//   const sessionUrl = new URL("/api/auth/get-session", request.url);

//   const response = await fetch(sessionUrl, {
//     headers: {
//       // Pass the user's cookies to the API
//       cookie: request.headers.get("cookie") || "",

//       // 2. THE AWS ALB FIX
//       // Tell Better Auth the original request was secure HTTPS, even if the ALB downgraded it to HTTP
//       "x-forwarded-proto": request.headers.get("x-forwarded-proto") || "https",
//     },
//   });

//   // Parse the session if the fetch was successful
//   const session = response.ok ? await response.json() : null;
//   const user = session?.user || null;

//   if (isProtectedRoute) {
//     // If no session exists, redirect to home page
//     if (!user) {
//       return NextResponse.redirect(new URL("/", request.url));
//     }
//   }

//   // If user is logged in and trying to access home page, redirect to dashboard
//   if (pathname === "/") {
//     if (user) {
//       return NextResponse.redirect(new URL("/dashboard", request.url));
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

import { NextRequest, NextResponse } from "next/server";

export async function middleware(request: NextRequest) {
  const pathname = request.nextUrl.pathname;

  // Routes that require authentication
  const protectedRoutes = ["/dashboard", "/tasks", "/settings"];

  // Check if current route is protected
  const isProtectedRoute = protectedRoutes.some((route) =>
    pathname.startsWith(route),
  );

  // 1. THE EDGE-SAFE SESSION FETCH
  // We ping the Better Auth endpoint internally instead of importing the MongoDB auth library
  const sessionUrl = new URL("/api/auth/get-session", request.url);

  const response = await fetch(sessionUrl, {
    headers: {
      // Pass the user's cookies to the API
      cookie: request.headers.get("cookie") || "",

      // 2. THE AWS ALB FIX
      // Tell Better Auth the original request was secure HTTPS, even if the ALB downgraded it to HTTP
      "x-forwarded-proto": request.headers.get("x-forwarded-proto") || "https",
    },
  });

  // Parse the session if the fetch was successful
  const session = response.ok ? await response.json() : null;
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
