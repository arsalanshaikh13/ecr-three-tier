"use client";

import Link from "next/link";
import { useState, useRef, useEffect } from "react";
import { useRouter } from "next/navigation";
import { authClient, signOut } from "@/lib/auth-client";

export default function Navigation() {
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const router = useRouter();
  const { data: sessionData } = authClient.useSession();

  // Close dropdown when clicking outside
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(event.target as Node)
      ) {
        setIsDropdownOpen(false);
      }
    }

    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const handleLogout = async () => {
    setIsDropdownOpen(false);
    try {
      await signOut({
        fetchOptions: {
          onSuccess: () => {
            // 1. Define your Cognito endpoints
            // Make sure these match your actual Terraform output/environment variables!
            const cognitoDomain =
              process.env.COGNITO_DOMAIN ||
              "https://auth-devsandbox-space.auth.us-east-1.amazoncognito.com";
            const clientId =
              process.env.COGNITO_CLIENT_ID || "YOUR_ACTUAL_CLIENT_ID";

            // 2. Define where Cognito should send the user AFTER destroying the cookie
            // It MUST match one of the "logout_urls" you defined in your Terraform app client!
            const logoutUri = "https://devsandbox.space/api/auth-logout";

            // 3. Instead of using router.push("/"), redirect the browser directly to Cognito
            window.location.href = `${cognitoDomain}/logout?client_id=${clientId}&logout_uri=${encodeURIComponent(logoutUri)}`;
          },
        },
      });
    } catch (error) {
      console.error("Logout failed:", error);
    }
  };
  return (
    <nav className="bg-white dark:bg-zinc-950 border-b border-zinc-200 dark:border-zinc-800 shadow-sm">
      <div className="px-6 py-4 flex items-center justify-between max-w-7xl mx-auto">
        {/* Left side - Logo/Title */}
        <div className="flex items-center gap-8">
          <Link
            href="/dashboard"
            className="text-xl font-semibold text-zinc-900 dark:text-white"
          >
            Task Manager
          </Link>
          <Link
            href="/tasks"
            className="text-sm font-medium text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white transition-colors"
          >
            Tasks
          </Link>
        </div>

        {/* Right side - User menu */}
        <div className="flex items-center gap-4">
          <div>Welcome {sessionData?.user.name}</div>
          <div className="relative" ref={dropdownRef}>
            <button
              onClick={() => setIsDropdownOpen(!isDropdownOpen)}
              className="flex items-center justify-center w-10 h-10 rounded-full bg-zinc-100 dark:bg-zinc-800 hover:bg-zinc-200 dark:hover:bg-zinc-700 transition-colors"
              aria-label="User menu"
            >
              <svg
                className="w-6 h-6 text-zinc-600 dark:text-zinc-400"
                fill="currentColor"
                viewBox="0 0 20 20"
              >
                <path
                  fillRule="evenodd"
                  d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z"
                  clipRule="evenodd"
                />
              </svg>
            </button>

            {/* Dropdown menu */}
            {isDropdownOpen && (
              <div className="absolute right-0 mt-2 w-48 bg-white dark:bg-zinc-900 rounded-lg shadow-lg border border-zinc-200 dark:border-zinc-700 z-50">
                <Link
                  href="/settings"
                  onClick={() => setIsDropdownOpen(false)}
                  className="block w-full text-left px-4 py-3 text-sm text-zinc-700 dark:text-zinc-300 hover:bg-zinc-100 dark:hover:bg-zinc-800 rounded-lg transition-colors first:rounded-t-lg"
                >
                  Settings
                </Link>
                <button
                  onClick={handleLogout}
                  className="w-full text-left px-4 py-3 text-sm text-zinc-700 dark:text-zinc-300 hover:bg-zinc-100 dark:hover:bg-zinc-800 rounded-lg transition-colors last:rounded-b-lg"
                >
                  Logout
                </button>
              </div>
            )}
          </div>
        </div>
      </div>
    </nav>
  );
}
