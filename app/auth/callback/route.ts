import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const next = request.nextUrl.searchParams.get("next") ?? "/app";
  let destination = new URL("/app", request.url);
  if (next.startsWith("/") && !next.startsWith("//") && !next.includes("\\")) {
    const candidate = new URL(next, request.url);
    if (candidate.origin === request.nextUrl.origin && candidate.pathname !== "/auth/callback") destination = candidate;
  }
  const response = NextResponse.redirect(destination);
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const failure = () => {
    const redirect = NextResponse.redirect(new URL("/masuk?error=callback", request.url));
    response.cookies.getAll().forEach(cookie => redirect.cookies.set(cookie));
    return redirect;
  };
  if (!code || !url || !key) return failure();
  try {
    const client = createServerClient(url, key, {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll(values: { name: string; value: string; options: CookieOptions }[]) {
          values.forEach(({ name, value, options }) => {
            request.cookies.set(name, value);
            response.cookies.set(name, value, options);
          });
        },
      },
    });
    const { error } = await client.auth.exchangeCodeForSession(code);
    if (error) return failure();
    return response;
  } catch { return failure(); }
}
