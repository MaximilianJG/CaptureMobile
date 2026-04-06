//
//  SupabaseManager.swift
//  CaptureMobile
//

import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: "https://dsvjisbxpqjotuakbrwq.supabase.co")!,
            supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRzdmppc2J4cHFqb3R1YWticndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0Nzc2MTgsImV4cCI6MjA5MTA1MzYxOH0.xhSFJ5ikMGtjIGtEKZ-MKnTqs2Cp4J2SmvyKfq4TWZw"
        )
    }

    /// Cached Supabase user UUID, set after successful sign-in.
    var currentUserID: String?
}
