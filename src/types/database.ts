/**
 * Supabase database types — `public` schema.
 *
 * Hand-authored to match `supabase gen types typescript --local` output exactly,
 * derived from supabase/migrations (the authoritative schema). Regenerate with
 * `npm run gen:types` once the local stack is running — the shape is identical,
 * so it is a drop-in replacement.
 *
 * Covers every table/view/enum/function in the current schema, including
 * 20260907120000_platform_admin (platform_role, admin read models/RPCs).
 */

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export interface Database {
  public: {
    Tables: {
      currencies: {
        Row: { code: string; name: string; minor_unit: number; symbol: string | null };
        Insert: { code: string; name: string; minor_unit: number; symbol?: string | null };
        Update: { code?: string; name?: string; minor_unit?: number; symbol?: string | null };
        Relationships: [];
      };
      users: {
        Row: {
          id: string;
          email: string;
          display_name: string;
          avatar_url: string | null;
          timezone: string;
          default_currency: string;
          notification_prefs: Json;
          platform_role: Database["public"]["Enums"]["platform_role"];
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          email: string;
          display_name: string;
          avatar_url?: string | null;
          timezone?: string;
          default_currency?: string;
          notification_prefs?: Json;
          platform_role?: Database["public"]["Enums"]["platform_role"];
        };
        Update: {
          display_name?: string;
          avatar_url?: string | null;
          timezone?: string;
          default_currency?: string;
          notification_prefs?: Json;
          platform_role?: Database["public"]["Enums"]["platform_role"];
        };
        Relationships: [];
      };
      projects: {
        Row: {
          id: string;
          name: string;
          description: string | null;
          status: Database["public"]["Enums"]["project_status"];
          profile: Database["public"]["Enums"]["project_profile"];
          module_visibility: Json;
          starts_on: string | null;
          ends_on: string | null;
          timezone: string;
          currency: string;
          cover_theme: string | null;
          health_config: Json;
          notes: string | null;
          created_by: string | null;
          created_at: string;
          updated_at: string;
          archived_at: string | null;
          deleted_at: string | null;
        };
        Insert: {
          name: string;
          timezone: string;
          currency: string;
          profile?: Database["public"]["Enums"]["project_profile"];
          module_visibility?: Json;
          description?: string | null;
          starts_on?: string | null;
          ends_on?: string | null;
          cover_theme?: string | null;
          notes?: string | null;
        };
        Update: {
          name?: string;
          description?: string | null;
          status?: Database["public"]["Enums"]["project_status"];
          profile?: Database["public"]["Enums"]["project_profile"];
          module_visibility?: Json;
          starts_on?: string | null;
          ends_on?: string | null;
          cover_theme?: string | null;
          health_config?: Json;
          notes?: string | null;
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      project_members: {
        Row: {
          id: string;
          project_id: string;
          user_id: string | null;
          display_name: string;
          email: string | null;
          role: Database["public"]["Enums"]["member_role"];
          status: Database["public"]["Enums"]["member_status"];
          invited_at: string | null;
          joined_at: string | null;
          removed_at: string | null;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          project_id: string;
          display_name: string;
          user_id?: string | null;
          email?: string | null;
          role?: Database["public"]["Enums"]["member_role"];
          status?: Database["public"]["Enums"]["member_status"];
        };
        Update: {
          display_name?: string;
          email?: string | null;
          role?: Database["public"]["Enums"]["member_role"];
          status?: Database["public"]["Enums"]["member_status"];
        };
        Relationships: [];
      };
      invitations: {
        Row: {
          id: string;
          project_id: string;
          email: string;
          role: Database["public"]["Enums"]["member_role"];
          status: Database["public"]["Enums"]["invitation_status"];
          token: string;
          invited_by: string;
          expires_at: string;
          created_at: string;
          updated_at: string;
          accepted_at: string | null;
          accepted_member_id: string | null;
        };
        Insert: {
          project_id: string;
          email: string;
          invited_by: string;
          role?: Database["public"]["Enums"]["member_role"];
          status?: Database["public"]["Enums"]["invitation_status"];
          token?: string;
          expires_at?: string;
        };
        Update: {
          status?: Database["public"]["Enums"]["invitation_status"];
          accepted_at?: string | null;
          accepted_member_id?: string | null;
        };
        Relationships: [];
      };
      commitments: {
        Row: {
          id: string;
          project_id: string;
          title: string;
          kind: Database["public"]["Enums"]["commitment_kind"];
          activity_type: Database["public"]["Enums"]["activity_type"];
          status: Database["public"]["Enums"]["commitment_status"];
          owner_member_id: string | null;
          estimated_cost_minor: number | null;
          confirmed_cost_minor: number | null;
          starts_at: string | null;
          ends_at: string | null;
          is_all_day: boolean;
          schedule_note: string | null;
          location_label: string | null;
          location_address: string | null;
          location_lat: number | null;
          location_lng: number | null;
          location_place_id: string | null;
          supplier_name: string | null;
          supplier_contact: string | null;
          booking_reference: string | null;
          booking_confirmed: boolean;
          notes: string | null;
          recurrence_frequency: Database["public"]["Enums"]["recurrence_frequency"] | null;
          recurrence_interval: number | null;
          recurrence_start_date: string | null;
          recurrence_end_date: string | null;
          recurrence_active: boolean;
          created_by: string | null;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          project_id: string;
          title: string;
          kind: Database["public"]["Enums"]["commitment_kind"];
          activity_type?: Database["public"]["Enums"]["activity_type"];
          status?: Database["public"]["Enums"]["commitment_status"];
          owner_member_id?: string | null;
          estimated_cost_minor?: number | null;
          confirmed_cost_minor?: number | null;
          starts_at?: string | null;
          ends_at?: string | null;
          is_all_day?: boolean;
          schedule_note?: string | null;
          location_label?: string | null;
          location_address?: string | null;
          location_lat?: number | null;
          location_lng?: number | null;
          location_place_id?: string | null;
          supplier_name?: string | null;
          supplier_contact?: string | null;
          booking_reference?: string | null;
          booking_confirmed?: boolean;
          notes?: string | null;
          recurrence_frequency?: Database["public"]["Enums"]["recurrence_frequency"] | null;
          recurrence_interval?: number | null;
          recurrence_start_date?: string | null;
          recurrence_end_date?: string | null;
          recurrence_active?: boolean;
        };
        Update: Partial<Database["public"]["Tables"]["commitments"]["Insert"]> & {
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      commitment_participants: {
        Row: {
          id: string;
          project_id: string;
          commitment_id: string;
          member_id: string;
          rsvp: Database["public"]["Enums"]["rsvp_status"];
          added_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          project_id: string;
          commitment_id: string;
          member_id: string;
          rsvp?: Database["public"]["Enums"]["rsvp_status"];
        };
        Update: { rsvp?: Database["public"]["Enums"]["rsvp_status"] };
        Relationships: [];
      };
      cost_shares: {
        Row: {
          id: string;
          project_id: string;
          commitment_id: string;
          member_id: string;
          basis: Database["public"]["Enums"]["cost_share_basis"];
          weight: number | null;
          fixed_amount_minor: number | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          project_id: string;
          commitment_id: string;
          member_id: string;
          basis: Database["public"]["Enums"]["cost_share_basis"];
          weight?: number | null;
          fixed_amount_minor?: number | null;
        };
        Update: {
          basis?: Database["public"]["Enums"]["cost_share_basis"];
          weight?: number | null;
          fixed_amount_minor?: number | null;
        };
        Relationships: [];
      };
      payments: {
        Row: {
          id: string;
          project_id: string;
          commitment_id: string;
          type: Database["public"]["Enums"]["payment_type"];
          direction: Database["public"]["Enums"]["payment_direction"];
          status: Database["public"]["Enums"]["payment_status"];
          amount_minor: number;
          due_on: string | null;
          paid_on: string | null;
          ever_paid: boolean;
          paid_by_member_id: string | null;
          method: string | null;
          reference: string | null;
          notes: string | null;
          created_by: string | null;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          project_id: string;
          commitment_id: string;
          type: Database["public"]["Enums"]["payment_type"];
          amount_minor: number;
          direction?: Database["public"]["Enums"]["payment_direction"];
          status?: Database["public"]["Enums"]["payment_status"];
          due_on?: string | null;
          paid_on?: string | null;
          paid_by_member_id?: string | null;
          method?: string | null;
          reference?: string | null;
          notes?: string | null;
        };
        Update: Partial<Database["public"]["Tables"]["payments"]["Insert"]> & {
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      tasks: {
        Row: {
          id: string;
          project_id: string;
          commitment_id: string | null;
          title: string;
          status: Database["public"]["Enums"]["task_status"];
          assignee_member_id: string | null;
          due_on: string | null;
          notes: string | null;
          completed_at: string | null;
          recurrence_frequency: Database["public"]["Enums"]["recurrence_frequency"] | null;
          recurrence_interval: number | null;
          recurrence_start_date: string | null;
          recurrence_end_date: string | null;
          recurrence_active: boolean;
          created_by: string | null;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Insert: {
          project_id: string;
          title: string;
          commitment_id?: string | null;
          status?: Database["public"]["Enums"]["task_status"];
          assignee_member_id?: string | null;
          due_on?: string | null;
          notes?: string | null;
          recurrence_frequency?: Database["public"]["Enums"]["recurrence_frequency"] | null;
          recurrence_interval?: number | null;
          recurrence_start_date?: string | null;
          recurrence_end_date?: string | null;
          recurrence_active?: boolean;
        };
        Update: Partial<Database["public"]["Tables"]["tasks"]["Insert"]> & {
          status?: Database["public"]["Enums"]["task_status"];
          deleted_at?: string | null;
        };
        Relationships: [];
      };
      commitment_occurrences: {
        Row: {
          id: string;
          project_id: string;
          commitment_id: string;
          occurrence_date: string;
          status: Database["public"]["Enums"]["occurrence_status"];
          completed_at: string | null;
          skipped_at: string | null;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          project_id: string;
          commitment_id: string;
          occurrence_date: string;
          status: Database["public"]["Enums"]["occurrence_status"];
          completed_at?: string | null;
          skipped_at?: string | null;
          created_by?: string | null;
        };
        Update: {
          status?: Database["public"]["Enums"]["occurrence_status"];
          completed_at?: string | null;
          skipped_at?: string | null;
        };
        Relationships: [];
      };
      task_occurrences: {
        Row: {
          id: string;
          project_id: string;
          task_id: string;
          occurrence_date: string;
          status: Database["public"]["Enums"]["occurrence_status"];
          completed_at: string | null;
          skipped_at: string | null;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          project_id: string;
          task_id: string;
          occurrence_date: string;
          status: Database["public"]["Enums"]["occurrence_status"];
          completed_at?: string | null;
          skipped_at?: string | null;
          created_by?: string | null;
        };
        Update: {
          status?: Database["public"]["Enums"]["occurrence_status"];
          completed_at?: string | null;
          skipped_at?: string | null;
        };
        Relationships: [];
      };
      milestones: {
        Row: {
          id: string;
          project_id: string;
          commitment_id: string | null;
          title: string;
          on_date: string;
          notes: string | null;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          project_id: string;
          title: string;
          on_date: string;
          commitment_id?: string | null;
          notes?: string | null;
        };
        Update: { title?: string; on_date?: string; notes?: string | null; commitment_id?: string | null };
        Relationships: [];
      };
      budgets: {
        Row: { project_id: string; total_target_minor: number | null; created_at: string; updated_at: string };
        Insert: { project_id: string; total_target_minor?: number | null };
        Update: { total_target_minor?: number | null };
        Relationships: [];
      };
      budget_category_targets: {
        Row: {
          project_id: string;
          kind: Database["public"]["Enums"]["commitment_kind"];
          amount_minor: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          project_id: string;
          kind: Database["public"]["Enums"]["commitment_kind"];
          amount_minor: number;
        };
        Update: { amount_minor?: number };
        Relationships: [];
      };
      finding_dismissals: {
        Row: {
          id: string;
          project_id: string;
          code: string;
          subject_type: string;
          subject_id: string | null;
          state: Database["public"]["Enums"]["finding_dismissal_state"];
          snoozed_until: string | null;
          actor_member_id: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          project_id: string;
          code: string;
          subject_type: string;
          state: Database["public"]["Enums"]["finding_dismissal_state"];
          subject_id?: string | null;
          snoozed_until?: string | null;
          actor_member_id?: string | null;
        };
        Update: {
          state?: Database["public"]["Enums"]["finding_dismissal_state"];
          snoozed_until?: string | null;
        };
        Relationships: [];
      };
      audit_log: {
        Row: {
          id: string;
          project_id: string | null;
          at: string;
          actor_user_id: string | null;
          actor_member_id: string | null;
          source: Database["public"]["Enums"]["audit_source"];
          action: Database["public"]["Enums"]["audit_action"];
          entity_type: string;
          entity_id: string;
          before: Json | null;
          after: Json | null;
          request_id: string | null;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
    };
    Views: {
      v_my_projects: {
        Row: {
          project_id: string;
          name: string;
          status: Database["public"]["Enums"]["project_status"];
          profile: Database["public"]["Enums"]["project_profile"];
          module_visibility: Json;
          starts_on: string | null;
          ends_on: string | null;
          timezone: string;
          currency: string;
          my_role: Database["public"]["Enums"]["member_role"];
          total_cost_minor: number | null;
          committed_spend_minor: number | null;
          net_actual_spend_minor: number | null;
          outstanding_minor: number | null;
          remaining_budget_minor: number | null;
          progress_pct: number | null;
          health_status: string | null;
          attention_count: number | null;
          next_event_at: string | null;
          total_target_minor: number | null;
        };
        Relationships: [];
      };
      v_project_financials: {
        Row: {
          project_id: string;
          total_cost_minor: number;
          committed_spend_minor: number;
          gross_paid_minor: number;
          refunded_minor: number;
          net_actual_spend_minor: number;
          outstanding_minor: number;
          scheduled_outstanding_minor: number;
          total_target_minor: number | null;
          remaining_budget_minor: number | null;
          projected_variance_minor: number | null;
          settled_variance_minor: number | null;
          progress_pct: number;
          commitment_count: number;
          open_commitment_count: number;
        };
        Relationships: [];
      };
      v_project_overview: {
        Row: {
          project_id: string;
          profile: Database["public"]["Enums"]["project_profile"];
          starts_on: string | null;
          ends_on: string | null;
          days_until_start: number | null;
          days_until_end: number | null;
          activity_count: number;
          open_activity_count: number;
          completed_activity_count: number;
          booking_count: number;
          booked_booking_count: number;
          task_count: number;
          purchase_count: number;
          event_count: number;
          overdue_activity_count: number;
          unowned_activity_count: number;
          supplier_count: number;
          active_member_count: number;
          milestone_count: number;
          upcoming_milestone_count: number;
          next_milestone_on: string | null;
          payment_overdue_count: number;
          payment_due_soon_count: number;
          total_cost_minor: number | null;
          committed_spend_minor: number | null;
          net_actual_spend_minor: number | null;
          outstanding_minor: number | null;
          total_target_minor: number | null;
          remaining_budget_minor: number | null;
          progress_pct: number | null;
          health_status: string | null;
          attention_count: number | null;
        };
        Relationships: [];
      };
      v_commitment_financials: {
        Row: {
          commitment_id: string;
          project_id: string;
          status: Database["public"]["Enums"]["commitment_status"];
          effective_cost_minor: number;
          gross_paid_minor: number;
          refunded_minor: number;
          net_paid_minor: number;
          outstanding_minor: number;
          payment_progress: string;
        };
        Relationships: [];
      };
      v_budget_category_actuals: {
        Row: {
          project_id: string;
          kind: Database["public"]["Enums"]["commitment_kind"];
          target_minor: number | null;
          actual_minor: number;
          variance_minor: number | null;
        };
        Relationships: [];
      };
      v_member_balances: {
        Row: {
          project_id: string;
          member_id: string;
          display_name: string;
          member_status: Database["public"]["Enums"]["member_status"];
          owed_minor: number;
          contributed_minor: number;
          balance_minor: number;
        };
        Relationships: [];
      };
      v_timeline_events: {
        Row: {
          project_id: string;
          occurs_at: string;
          all_day: boolean;
          event_type: string;
          title: string;
          subject_type: string;
          subject_id: string;
          status: string | null;
          occurrence_date: string | null;
          series_id: string | null;
          is_recurring_occurrence: boolean;
          occurrence_status: string | null;
        };
        Relationships: [];
      };
      v_my_timeline_events: {
        Row: {
          project_id: string;
          project_name: string;
          project_timezone: string;
          currency: string;
          occurs_at: string;
          all_day: boolean;
          event_type: string;
          title: string;
          subject_type: string;
          subject_id: string;
          status: string | null;
          amount_minor: number | null;
          occurrence_date: string | null;
          series_id: string | null;
          is_recurring_occurrence: boolean;
          occurrence_status: string | null;
        };
        Relationships: [];
      };
      v_member_directory: {
        Row: {
          project_id: string;
          member_id: string;
          display_name: string;
          avatar_url: string | null;
          role: Database["public"]["Enums"]["member_role"];
          status: Database["public"]["Enums"]["member_status"];
        };
        Relationships: [];
      };
      v_my_people: {
        Row: {
          person_key: string;
          user_id: string | null;
          display_name: string;
          avatar_url: string | null;
          is_current_user: boolean;
          project_count: number;
          roles: Database["public"]["Enums"]["member_role"][];
          projects: Json;
        };
        Relationships: [];
      };
      v_admin_users: {
        Row: {
          id: string;
          email: string;
          display_name: string;
          avatar_url: string | null;
          timezone: string;
          default_currency: string;
          platform_role: Database["public"]["Enums"]["platform_role"];
          created_at: string;
          updated_at: string;
          membership_count: number;
          active_membership_count: number;
        };
        Relationships: [];
      };
      v_admin_user_memberships: {
        Row: {
          member_id: string;
          project_id: string;
          project_name: string;
          project_status: Database["public"]["Enums"]["project_status"];
          user_id: string | null;
          display_name: string;
          email: string | null;
          role: Database["public"]["Enums"]["member_role"];
          status: Database["public"]["Enums"]["member_status"];
          joined_at: string | null;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Relationships: [];
      };
      v_admin_projects: {
        Row: {
          id: string;
          name: string;
          description: string | null;
          status: Database["public"]["Enums"]["project_status"];
          starts_on: string | null;
          ends_on: string | null;
          timezone: string;
          currency: string;
          created_by: string | null;
          created_by_display_name: string | null;
          created_by_email: string | null;
          created_at: string;
          updated_at: string;
          archived_at: string | null;
          deleted_at: string | null;
          member_count: number;
          active_member_count: number;
          commitment_count: number;
          total_cost_minor: number;
          gross_paid_minor: number;
        };
        Relationships: [];
      };
      v_admin_project_members: {
        Row: {
          id: string;
          project_id: string;
          user_id: string | null;
          display_name: string;
          email: string | null;
          role: Database["public"]["Enums"]["member_role"];
          status: Database["public"]["Enums"]["member_status"];
          platform_role: Database["public"]["Enums"]["platform_role"] | null;
          joined_at: string | null;
          created_at: string;
          updated_at: string;
          deleted_at: string | null;
        };
        Relationships: [];
      };
      v_admin_invitations: {
        Row: {
          id: string;
          project_id: string;
          project_name: string;
          email: string;
          role: Database["public"]["Enums"]["member_role"];
          status: Database["public"]["Enums"]["invitation_status"];
          inviter_display_name: string | null;
          inviter_email: string | null;
          created_at: string;
          updated_at: string;
          expires_at: string;
          accepted_at: string | null;
        };
        Relationships: [];
      };
      v_admin_audit_log: {
        Row: {
          id: string;
          project_id: string | null;
          project_name: string | null;
          at: string;
          actor_user_id: string | null;
          actor_email: string | null;
          actor_display_name: string | null;
          actor_member_id: string | null;
          source: Database["public"]["Enums"]["audit_source"];
          action: Database["public"]["Enums"]["audit_action"];
          entity_type: string;
          entity_id: string;
          request_id: string | null;
          before: Json | null;
          after: Json | null;
        };
        Relationships: [];
      };
    };
    Functions: {
      create_invitation: { Args: { p_project_id: string; p_email: string; p_role: MemberRole }; Returns: string };
      decline_invitation: { Args: { p_token: string }; Returns: string };
      list_my_invitations: { Args: Record<string, never>; Returns: { id: string; project_id: string; token: string; project_name: string; inviter_name: string | null; role: MemberRole; created_at: string }[] };

      soft_delete_commitment: { Args: { p_commitment: string }; Returns: string };
      soft_delete_task: { Args: { p_task: string }; Returns: string };
      soft_delete_project: { Args: { p_project: string }; Returns: string };

      create_project: {
        Args: {
          p_name: string;
          p_timezone: string;
          p_currency: string;
          p_starts_on?: string | null;
          p_ends_on?: string | null;
          p_profile?: Database["public"]["Enums"]["project_profile"];
        };
        Returns: string;
      };
      get_project_health: {
        Args: { p_project: string };
        Returns: {
          code: string;
          severity: string;
          subject_type: string;
          subject_id: string | null;
          subject_label: string | null;
          params: Json;
          message: string;
          resolution: string;
          affects_health: boolean;
          dismissible: boolean;
          dismissed: boolean;
          snoozed_until: string | null;
        }[];
      };
      get_project_health_summary: {
        Args: { p_project: string };
        Returns: {
          status: string;
          blocker_count: number;
          warning_count: number;
          info_count: number;
          attention_count: number;
        }[];
      };
      get_project_timeline_events: {
        Args: { p_project: string; p_start: string; p_end: string };
        Returns: {
          project_id: string;
          occurs_at: string;
          all_day: boolean;
          event_type: string;
          title: string;
          subject_type: string;
          subject_id: string;
          status: string | null;
          occurrence_date: string | null;
          series_id: string | null;
          is_recurring_occurrence: boolean;
          occurrence_status: string | null;
        }[];
      };
      get_my_timeline_events: {
        Args: { p_start: string; p_end: string };
        Returns: {
          project_id: string;
          project_name: string;
          project_timezone: string;
          currency: string;
          occurs_at: string;
          all_day: boolean;
          event_type: string;
          title: string;
          subject_type: string;
          subject_id: string;
          status: string | null;
          amount_minor: number | null;
          occurrence_date: string | null;
          series_id: string | null;
          is_recurring_occurrence: boolean;
          occurrence_status: string | null;
        }[];
      };
      get_commitment_occurrences: {
        Args: { p_commitment: string; p_start: string; p_end: string };
        Returns: {
          project_id: string;
          commitment_id: string;
          occurrence_date: string;
          status: string;
          completed_at: string | null;
          skipped_at: string | null;
        }[];
      };
      get_task_occurrences: {
        Args: { p_task: string; p_start: string; p_end: string };
        Returns: {
          project_id: string;
          task_id: string;
          occurrence_date: string;
          status: string;
          completed_at: string | null;
          skipped_at: string | null;
        }[];
      };
      complete_commitment_occurrence: {
        Args: { p_commitment: string; p_occurrence_date: string };
        Returns: undefined;
      };
      skip_commitment_occurrence: {
        Args: { p_commitment: string; p_occurrence_date: string };
        Returns: undefined;
      };
      stop_commitment_recurrence: {
        Args: { p_commitment: string; p_stop_after: string };
        Returns: undefined;
      };
      complete_task_occurrence: {
        Args: { p_task: string; p_occurrence_date: string };
        Returns: undefined;
      };
      skip_task_occurrence: {
        Args: { p_task: string; p_occurrence_date: string };
        Returns: undefined;
      };
      stop_task_recurrence: {
        Args: { p_task: string; p_stop_after: string };
        Returns: undefined;
      };
      get_my_attention: {
        Args: Record<PropertyKey, never>;
        Returns: {
          project_id: string;
          project_name: string;
          code: string;
          severity: string;
          subject_type: string;
          subject_id: string | null;
          subject_label: string | null;
          params: Json;
          message: string;
          resolution: string;
        }[];
      };
      get_invitation: {
        Args: { p_token: string };
        Returns: {
          project_name: string;
          inviter_name: string | null;
          role: Database["public"]["Enums"]["member_role"];
          status: Database["public"]["Enums"]["invitation_status"];
        }[];
      };
      accept_invitation: {
        Args: { p_token: string };
        Returns: string;
      };
      transfer_and_leave: {
        Args: { p_project: string; p_new_organizer_member: string };
        Returns: undefined;
      };
      get_admin_overview: {
        Args: Record<PropertyKey, never>;
        Returns: {
          total_users: number;
          admin_users: number;
          total_projects: number;
          active_projects: number;
          archived_projects: number;
          deleted_projects: number;
          pending_invitations: number;
          active_invitations: number;
        }[];
      };
      get_admin_project_health_summary: {
        Args: { p_project: string };
        Returns: {
          status: string;
          blocker_count: number;
          warning_count: number;
          info_count: number;
          attention_count: number;
        }[];
      };
    };
    Enums: {
      activity_type: "task" | "booking" | "purchase" | "event" | "other";
      recurrence_frequency: "weekly" | "monthly";
      occurrence_status: "completed" | "skipped";
      platform_role: "user" | "admin";
      project_profile:
        | "group_trip"
        | "wedding_event"
        | "house_move"
        | "recurring_process"
        | "team_project"
        | "launch"
        | "blank";
      project_status: "draft" | "active" | "completed" | "archived";
      member_role: "organizer" | "member" | "viewer";
      member_status: "invited" | "active" | "removed";
      invitation_status: "pending" | "accepted" | "expired" | "revoked" | "declined";
      commitment_kind: "accommodation" | "transport" | "food" | "experience" | "services" | "other";
      commitment_status: "idea" | "researching" | "confirmed" | "booked" | "completed" | "cancelled";
      payment_type: "deposit" | "balance" | "installment" | "full" | "refund";
      payment_direction: "outgoing" | "incoming";
      payment_status: "scheduled" | "paid" | "waived" | "cancelled";
      task_status: "open" | "in_progress" | "done" | "cancelled";
      cost_share_basis: "equal" | "weight" | "fixed";
      rsvp_status: "going" | "maybe" | "not_going" | "unknown";
      finding_dismissal_state: "dismissed" | "snoozed";
      audit_action: "create" | "update" | "soft_delete" | "restore" | "delete";
      audit_source: "app" | "rpc" | "edge" | "system";
    };
    CompositeTypes: Record<PropertyKey, never>;
  };
}

// ---- generated-style helper aliases -----------------------------------------
type PublicSchema = Database["public"];

export type Tables<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Row"];
export type TablesInsert<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Insert"];
export type TablesUpdate<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Update"];
export type Views<T extends keyof PublicSchema["Views"]> = PublicSchema["Views"][T]["Row"];
export type Enums<T extends keyof PublicSchema["Enums"]> = PublicSchema["Enums"][T];

// ---- convenience unions referenced across the app --------------------------
export type ProjectStatus = Enums<"project_status">;
export type ProjectProfile = Enums<"project_profile">;
export type ActivityType = Enums<"activity_type">;
export type RecurrenceFrequency = Enums<"recurrence_frequency">;
export type MemberRole = Enums<"member_role">;
export type MemberStatus = Enums<"member_status">;
export type PlatformRole = Enums<"platform_role">;
export type CommitmentKind = Enums<"commitment_kind">;
export type CommitmentStatus = Enums<"commitment_status">;
export type HealthStatus = "needs_attention" | "at_risk" | "healthy";
export type FindingSeverity = "blocker" | "warning" | "info" | "ok";

// Row shapes for the two health RPCs (used by services/composables).
export type HealthFindingRow = Database["public"]["Functions"]["get_project_health"]["Returns"][number];
export type HealthSummaryRow = Database["public"]["Functions"]["get_project_health_summary"]["Returns"][number];
export type MyAttentionRow = Database["public"]["Functions"]["get_my_attention"]["Returns"][number];
