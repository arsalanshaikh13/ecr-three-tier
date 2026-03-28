import { NextResponse } from "next/server";

export async function GET(request: Request) {
  // Catch the user returning from Cognito and immediately bounce them to the homepage
  return NextResponse.redirect(new URL("/", request.url));
}
