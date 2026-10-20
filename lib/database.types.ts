export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  audit: {
    Tables: {
      audit_events: {
        Row: {
          action: Database["audit"]["Enums"]["action"];
          actor_id: string | null;
          actor_roles: Json | null;
          actor_subject: string | null;
          actor_type: Database["core"]["Enums"]["actor_type"] | null;
          changed_fields: string[] | null;
          db_user: string;
          id: string;
          jwt_role: string | null;
          new_values: Json | null;
          occurred_at: string;
          old_values: Json | null;
          origin: Database["audit"]["Enums"]["change_origin"] | null;
          reason: string | null;
          record_id: string;
          schema_name: string;
          scope_brand_id: string | null;
          scope_group_id: string | null;
          scope_restaurant_id: string | null;
          sequence_number: number;
          table_name: string;
          transaction_id: number;
          event_digest: string | null;
        };
        ComputedFields: "event_digest";
        Insert: {
          action: Database["audit"]["Enums"]["action"];
          actor_id?: string | null;
          actor_roles?: Json | null;
          actor_subject?: string | null;
          actor_type?: Database["core"]["Enums"]["actor_type"] | null;
          changed_fields?: string[] | null;
          db_user?: string;
          id?: string;
          jwt_role?: string | null;
          new_values?: Json | null;
          occurred_at?: string;
          old_values?: Json | null;
          origin?: Database["audit"]["Enums"]["change_origin"] | null;
          reason?: string | null;
          record_id: string;
          schema_name: string;
          scope_brand_id?: string | null;
          scope_group_id?: string | null;
          scope_restaurant_id?: string | null;
          sequence_number?: never;
          table_name: string;
          transaction_id?: number;
        };
        Update: {
          action?: Database["audit"]["Enums"]["action"];
          actor_id?: string | null;
          actor_roles?: Json | null;
          actor_subject?: string | null;
          actor_type?: Database["core"]["Enums"]["actor_type"] | null;
          changed_fields?: string[] | null;
          db_user?: string;
          id?: string;
          jwt_role?: string | null;
          new_values?: Json | null;
          occurred_at?: string;
          old_values?: Json | null;
          origin?: Database["audit"]["Enums"]["change_origin"] | null;
          reason?: string | null;
          record_id?: string;
          schema_name?: string;
          scope_brand_id?: string | null;
          scope_group_id?: string | null;
          scope_restaurant_id?: string | null;
          sequence_number?: never;
          table_name?: string;
          transaction_id?: number;
        };
        Relationships: [];
      };
      audit_seals: {
        Row: {
          chain_hash: string;
          event_count: number;
          first_sequence: number;
          id: number;
          last_sequence: number;
          previous_hash: string;
          sealed_at: string;
        };
        ComputedFields: never;
        Insert: {
          chain_hash: string;
          event_count: number;
          first_sequence: number;
          id?: never;
          last_sequence: number;
          previous_hash: string;
          sealed_at?: string;
        };
        Update: {
          chain_hash?: string;
          event_count?: number;
          first_sequence?: number;
          id?: never;
          last_sequence?: number;
          previous_hash?: string;
          sealed_at?: string;
        };
        Relationships: [];
      };
      security_event_seals: {
        Row: {
          chain_hash: string;
          event_count: number;
          first_sequence: number;
          id: number;
          last_sequence: number;
          previous_hash: string;
          sealed_at: string;
        };
        ComputedFields: never;
        Insert: {
          chain_hash: string;
          event_count: number;
          first_sequence: number;
          id?: never;
          last_sequence: number;
          previous_hash: string;
          sealed_at?: string;
        };
        Update: {
          chain_hash?: string;
          event_count?: number;
          first_sequence?: number;
          id?: never;
          last_sequence?: number;
          previous_hash?: string;
          sealed_at?: string;
        };
        Relationships: [];
      };
      security_events: {
        Row: {
          actor_id: string | null;
          actor_subject: string | null;
          db_user: string;
          details: Json | null;
          email: string | null;
          event_type: Database["audit"]["Enums"]["security_event_type"];
          id: string;
          ip: string | null;
          jwt_role: string | null;
          occurred_at: string;
          operation: string | null;
          reason: string | null;
          scope_brand_id: string | null;
          scope_group_id: string | null;
          scope_restaurant_id: string | null;
          sequence_number: number;
          target_user_id: string | null;
          user_agent: string | null;
          security_event_digest: string | null;
        };
        ComputedFields: "security_event_digest";
        Insert: {
          actor_id?: string | null;
          actor_subject?: string | null;
          db_user?: string;
          details?: Json | null;
          email?: string | null;
          event_type: Database["audit"]["Enums"]["security_event_type"];
          id?: string;
          ip?: string | null;
          jwt_role?: string | null;
          occurred_at?: string;
          operation?: string | null;
          reason?: string | null;
          scope_brand_id?: string | null;
          scope_group_id?: string | null;
          scope_restaurant_id?: string | null;
          sequence_number?: never;
          target_user_id?: string | null;
          user_agent?: string | null;
        };
        Update: {
          actor_id?: string | null;
          actor_subject?: string | null;
          db_user?: string;
          details?: Json | null;
          email?: string | null;
          event_type?: Database["audit"]["Enums"]["security_event_type"];
          id?: string;
          ip?: string | null;
          jwt_role?: string | null;
          occurred_at?: string;
          operation?: string | null;
          reason?: string | null;
          scope_brand_id?: string | null;
          scope_group_id?: string | null;
          scope_restaurant_id?: string | null;
          sequence_number?: never;
          target_user_id?: string | null;
          user_agent?: string | null;
        };
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      event_digest: {
        Args: {
          p_event: Omit<
            Database["audit"]["Tables"]["audit_events"]["Row"],
            Database["audit"]["Tables"]["audit_events"]["ComputedFields"]
          >;
        };
        Returns: string;
      };
      genesis_hash: { Args: Record<PropertyKey, never>; Returns: string };
      is_sensitive_key: { Args: { p_key: string }; Returns: boolean };
      log_security_event: {
        Args: {
          p_brand_id?: string;
          p_details?: Json;
          p_email?: string;
          p_event_type: Database["audit"]["Enums"]["security_event_type"];
          p_group_id?: string;
          p_ip?: string;
          p_operation: string;
          p_reason: string;
          p_restaurant_id?: string;
          p_target_user_id?: string;
          p_user_agent?: string;
        };
        Returns: string;
      };
      redact: { Args: { p_excluded?: string[]; p_value: Json }; Returns: Json };
      seal_events: {
        Args: { p_min_age?: string };
        Returns: {
          chain_hash: string;
          event_count: number;
          first_sequence: number;
          id: number;
          last_sequence: number;
          previous_hash: string;
          sealed_at: string;
        };
        SetofOptions: {
          from: "*";
          to: "audit_seals";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      seal_security_events: {
        Args: { p_min_age?: string };
        Returns: {
          chain_hash: string;
          event_count: number;
          first_sequence: number;
          id: number;
          last_sequence: number;
          previous_hash: string;
          sealed_at: string;
        };
        SetofOptions: {
          from: "*";
          to: "security_event_seals";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      security_event_digest: {
        Args: {
          p_event: Omit<
            Database["audit"]["Tables"]["security_events"]["Row"],
            Database["audit"]["Tables"]["security_events"]["ComputedFields"]
          >;
        };
        Returns: string;
      };
      security_genesis_hash: { Args: Record<PropertyKey, never>; Returns: string };
      try_uuid: { Args: { p_value: string }; Returns: string };
      verify_seals: {
        Args: Record<PropertyKey, never>;
        Returns: {
          expected_events: number;
          found_events: number;
          is_valid: boolean;
          seal_id: number;
        }[];
      };
      verify_security_seals: {
        Args: Record<PropertyKey, never>;
        Returns: {
          expected_events: number;
          found_events: number;
          is_valid: boolean;
          seal_id: number;
        }[];
      };
    };
    Enums: {
      action: "insert" | "update" | "soft_delete" | "restore" | "delete";
      change_origin: "app" | "edge_function" | "agent" | "import" | "seed" | "maintenance";
      security_event_type:
        | "login_succeeded"
        | "login_failed"
        | "account_locked"
        | "account_unlocked"
        | "operation_denied"
        | "account_disabled"
        | "account_reactivated";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  core: {
    Tables: {
      actors: {
        Row: {
          actor_type: Database["core"]["Enums"]["actor_type"];
          created_at: string;
          id: string;
        };
        ComputedFields: never;
        Insert: {
          actor_type?: Database["core"]["Enums"]["actor_type"];
          created_at?: string;
          id: string;
        };
        Update: {
          actor_type?: Database["core"]["Enums"]["actor_type"];
          created_at?: string;
          id?: string;
        };
        Relationships: [];
      };
      permissions: {
        Row: {
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          description: string;
          id: string;
          is_sensitive: boolean;
          module: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          code: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description: string;
          id?: string;
          is_sensitive?: boolean;
          module: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string;
          id?: string;
          is_sensitive?: boolean;
          module?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "permissions_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "permissions_deleted_by_fkey";
            columns: ["deleted_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "permissions_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
        ];
      };
      role_permissions: {
        Row: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          id: string;
          permission_id: string;
          role_id: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          id?: string;
          permission_id: string;
          role_id: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          id?: string;
          permission_id?: string;
          role_id?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "role_permissions_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "role_permissions_deleted_by_fkey";
            columns: ["deleted_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "role_permissions_permission_id_fkey";
            columns: ["permission_id"];
            isOneToOne: false;
            referencedRelation: "permissions";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "role_permissions_role_id_fkey";
            columns: ["role_id"];
            isOneToOne: false;
            referencedRelation: "roles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "role_permissions_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
        ];
      };
      roles: {
        Row: {
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          description: string | null;
          id: string;
          is_system: boolean;
          level: number | null;
          name: string;
          requires_mfa: boolean;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          code: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          id?: string;
          is_system?: boolean;
          level?: number | null;
          name: string;
          requires_mfa?: boolean;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          id?: string;
          is_system?: boolean;
          level?: number | null;
          name?: string;
          requires_mfa?: boolean;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "roles_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "roles_deleted_by_fkey";
            columns: ["deleted_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "roles_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
        ];
      };
      service_accounts: {
        Row: {
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          description: string | null;
          id: string;
          name: string;
          owner_user_id: string;
          status: Database["core"]["Enums"]["account_status"];
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          code: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          id: string;
          name: string;
          owner_user_id: string;
          status?: Database["core"]["Enums"]["account_status"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          id?: string;
          name?: string;
          owner_user_id?: string;
          status?: Database["core"]["Enums"]["account_status"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "service_accounts_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "service_accounts_deleted_by_fkey";
            columns: ["deleted_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "service_accounts_id_fkey";
            columns: ["id"];
            isOneToOne: true;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "service_accounts_owner_user_id_fkey";
            columns: ["owner_user_id"];
            isOneToOne: false;
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "service_accounts_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
        ];
      };
      user_memberships: {
        Row: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          updated_at: string;
          updated_by: string | null;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          updated_at?: string;
          updated_by?: string | null;
          user_id: string;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          updated_at?: string;
          updated_by?: string | null;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "user_memberships_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_memberships_deleted_by_fkey";
            columns: ["deleted_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_memberships_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_memberships_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      user_profiles: {
        Row: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          disabled_at: string | null;
          disabled_reason: string | null;
          email: string;
          failed_login_count: number;
          first_name: string | null;
          id: string;
          last_failed_login_at: string | null;
          last_name: string | null;
          locked_until: string | null;
          status: Database["core"]["Enums"]["account_status"];
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          disabled_at?: string | null;
          disabled_reason?: string | null;
          email: string;
          failed_login_count?: number;
          first_name?: string | null;
          id: string;
          last_failed_login_at?: string | null;
          last_name?: string | null;
          locked_until?: string | null;
          status?: Database["core"]["Enums"]["account_status"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          disabled_at?: string | null;
          disabled_reason?: string | null;
          email?: string;
          failed_login_count?: number;
          first_name?: string | null;
          id?: string;
          last_failed_login_at?: string | null;
          last_name?: string | null;
          locked_until?: string | null;
          status?: Database["core"]["Enums"]["account_status"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "user_profiles_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_profiles_deleted_by_fkey";
            columns: ["deleted_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_profiles_id_fkey";
            columns: ["id"];
            isOneToOne: true;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_profiles_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
        ];
      };
      user_role_assignments: {
        Row: {
          brand_id: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          restaurant_id: string | null;
          role_id: string;
          scope_type: Database["core"]["Enums"]["scope_type"];
          updated_at: string;
          updated_by: string | null;
          user_id: string;
          valid_from: string;
          valid_until: string | null;
        };
        ComputedFields: never;
        Insert: {
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          restaurant_id?: string | null;
          role_id: string;
          scope_type: Database["core"]["Enums"]["scope_type"];
          updated_at?: string;
          updated_by?: string | null;
          user_id: string;
          valid_from?: string;
          valid_until?: string | null;
        };
        Update: {
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          restaurant_id?: string | null;
          role_id?: string;
          scope_type?: Database["core"]["Enums"]["scope_type"];
          updated_at?: string;
          updated_by?: string | null;
          user_id?: string;
          valid_from?: string;
          valid_until?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "user_role_assignments_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_role_assignments_deleted_by_fkey";
            columns: ["deleted_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_role_assignments_role_id_fkey";
            columns: ["role_id"];
            isOneToOne: false;
            referencedRelation: "roles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_role_assignments_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_role_assignments_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      actor_grants: {
        Args: { p_permission: string };
        Returns: {
          brand_id: string;
          group_id: string;
          restaurant_id: string;
          scope_type: Database["core"]["Enums"]["scope_type"];
        }[];
      };
      actor_roles_snapshot: { Args: { p_actor_id: string }; Returns: Json };
      apply_role_assignment: { Args: { p_request_id: string }; Returns: undefined };
      apply_role_permission_change: { Args: { p_request_id: string }; Returns: undefined };
      assign_role: {
        Args: {
          p_brand_id?: string;
          p_group_id: string;
          p_reason?: string;
          p_restaurant_id?: string;
          p_role_code: string;
          p_scope_type: Database["core"]["Enums"]["scope_type"];
          p_user_id: string;
          p_valid_until?: string;
        };
        Returns: Json;
      };
      can_view_scope: {
        Args: {
          p_brand_id?: string;
          p_group_id: string;
          p_permission: string;
          p_restaurant_id?: string;
          p_scope_type: Database["core"]["Enums"]["scope_type"];
        };
        Returns: boolean;
      };
      can_view_user: { Args: { p_user_id: string }; Returns: boolean };
      check_scope: {
        Args: {
          p_brand_id: string;
          p_group_id: string;
          p_restaurant_id: string;
          p_scope_type: Database["core"]["Enums"]["scope_type"];
        };
        Returns: undefined;
      };
      current_aal: { Args: Record<PropertyKey, never>; Returns: string };
      current_actor_id: { Args: Record<PropertyKey, never>; Returns: string };
      current_actor_subject: { Args: Record<PropertyKey, never>; Returns: string };
      current_session_ok: { Args: Record<PropertyKey, never>; Returns: boolean };
      deny: {
        Args: {
          p_brand_id?: string;
          p_details?: Json;
          p_group_id?: string;
          p_operation: string;
          p_reason: string;
          p_restaurant_id?: string;
          p_target_user_id?: string;
        };
        Returns: Json;
      };
      has_permission: { Args: { p_permission: string; p_restaurant_id: string }; Returns: boolean };
      has_permission_anywhere: { Args: { p_permission: string }; Returns: boolean };
      has_permission_for_scope: {
        Args: {
          p_brand_id?: string;
          p_group_id: string;
          p_permission: string;
          p_restaurant_id?: string;
          p_scope_type: Database["core"]["Enums"]["scope_type"];
        };
        Returns: boolean;
      };
      has_permission_in_brand: {
        Args: { p_brand_id: string; p_permission: string };
        Returns: boolean;
      };
      has_permission_in_group: {
        Args: { p_group_id: string; p_permission: string };
        Returns: boolean;
      };
      has_role_for_scope: {
        Args: {
          p_brand_id?: string;
          p_group_id: string;
          p_restaurant_id?: string;
          p_role_codes: string[];
          p_scope_type: Database["core"]["Enums"]["scope_type"];
        };
        Returns: boolean;
      };
      is_assignment_current: {
        Args: { p_valid_from: string; p_valid_until: string };
        Returns: boolean;
      };
      missing_permissions_for_role: {
        Args: {
          p_brand_id: string;
          p_group_id: string;
          p_restaurant_id: string;
          p_role_id: string;
          p_scope_type: Database["core"]["Enums"]["scope_type"];
        };
        Returns: string[];
      };
      permitted_restaurant_ids: { Args: { p_permission: string }; Returns: string[] };
      request_role_permission_change: {
        Args: {
          p_grant: boolean;
          p_group_id: string;
          p_permission_code: string;
          p_reason: string;
          p_role_code: string;
        };
        Returns: Json;
      };
      revoke_role: { Args: { p_assignment_id: string; p_reason: string }; Returns: Json };
      set_change_context: { Args: { p_origin: string; p_reason: string }; Returns: undefined };
      visible_assignment_ids: { Args: Record<PropertyKey, never>; Returns: string[] };
      visible_brand_ids: { Args: { p_permission: string }; Returns: string[] };
      visible_user_ids: { Args: Record<PropertyKey, never>; Returns: string[] };
    };
    Enums: {
      account_status: "active" | "disabled";
      actor_type: "user" | "service_account";
      scope_type: "group" | "brand" | "restaurant";
      version_status: "draft" | "in_review" | "approved" | "published" | "archived";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  org: {
    Tables: {
      areas: {
        Row: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          name: string;
          restaurant_id: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          name: string;
          restaurant_id: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          name?: string;
          restaurant_id?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "areas_group_id_fkey";
            columns: ["group_id"];
            isOneToOne: false;
            referencedRelation: "groups";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "areas_restaurant_fkey";
            columns: ["restaurant_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "restaurants";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      brands: {
        Row: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          name: string;
          status: Database["org"]["Enums"]["unit_status"];
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          name: string;
          status?: Database["org"]["Enums"]["unit_status"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          name?: string;
          status?: Database["org"]["Enums"]["unit_status"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "brands_group_id_fkey";
            columns: ["group_id"];
            isOneToOne: false;
            referencedRelation: "groups";
            referencedColumns: ["id"];
          },
        ];
      };
      groups: {
        Row: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          id: string;
          name: string;
          status: Database["org"]["Enums"]["unit_status"];
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          id?: string;
          name: string;
          status?: Database["org"]["Enums"]["unit_status"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          id?: string;
          name?: string;
          status?: Database["org"]["Enums"]["unit_status"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [];
      };
      restaurants: {
        Row: {
          address: string | null;
          brand_id: string;
          code: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          legal_name: string | null;
          locality: string | null;
          name: string;
          opened_on: string | null;
          phone: string | null;
          predecessor_id: string | null;
          status: Database["org"]["Enums"]["unit_status"];
          tax_id: string | null;
          time_zone: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          address?: string | null;
          brand_id: string;
          code?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          legal_name?: string | null;
          locality?: string | null;
          name: string;
          opened_on?: string | null;
          phone?: string | null;
          predecessor_id?: string | null;
          status?: Database["org"]["Enums"]["unit_status"];
          tax_id?: string | null;
          time_zone?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          address?: string | null;
          brand_id?: string;
          code?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          legal_name?: string | null;
          locality?: string | null;
          name?: string;
          opened_on?: string | null;
          phone?: string | null;
          predecessor_id?: string | null;
          status?: Database["org"]["Enums"]["unit_status"];
          tax_id?: string | null;
          time_zone?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "restaurants_brand_fkey";
            columns: ["brand_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "brands";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "restaurants_group_id_fkey";
            columns: ["group_id"];
            isOneToOne: false;
            referencedRelation: "groups";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "restaurants_predecessor_id_fkey";
            columns: ["predecessor_id"];
            isOneToOne: false;
            referencedRelation: "restaurants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "restaurants_time_zone_fkey";
            columns: ["time_zone"];
            isOneToOne: false;
            referencedRelation: "time_zones";
            referencedColumns: ["code"];
          },
        ];
      };
      time_zones: {
        Row: {
          code: string;
        };
        ComputedFields: never;
        Insert: {
          code: string;
        };
        Update: {
          code?: string;
        };
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      apply_transfer: { Args: { p_request_id: string }; Returns: undefined };
      check_keys: { Args: { p_allowed: string[]; p_changes: Json }; Returns: undefined };
      create_area: {
        Args: { p_name: string; p_reason: string; p_restaurant_id: string };
        Returns: string;
      };
      create_brand: {
        Args: { p_group_id: string; p_name: string; p_reason: string };
        Returns: string;
      };
      create_restaurant: {
        Args: { p_brand_id: string; p_details: Json; p_name: string; p_reason: string };
        Returns: string;
      };
      request_transfer: {
        Args: {
          p_new_name: string;
          p_reason: string;
          p_restaurant_id: string;
          p_target_brand_id: string;
        };
        Returns: Json;
      };
      require: { Args: { p_action: string; p_allowed: boolean }; Returns: undefined };
      set_deleted: {
        Args: { p_deleted: boolean; p_id: string; p_reason: string; p_table: string };
        Returns: undefined;
      };
      update_area: {
        Args: { p_changes: Json; p_id: string; p_reason: string };
        Returns: undefined;
      };
      update_brand: {
        Args: { p_changes: Json; p_id: string; p_reason: string };
        Returns: undefined;
      };
      update_group: {
        Args: { p_changes: Json; p_id: string; p_reason: string };
        Returns: undefined;
      };
      update_restaurant: {
        Args: { p_changes: Json; p_id: string; p_reason: string };
        Returns: undefined;
      };
    };
    Enums: {
      unit_status: "active" | "inactive";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  public: {
    Tables: {
      [_ in never]: never;
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      [_ in never]: never;
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  workflow: {
    Tables: {
      approval_decisions: {
        Row: {
          comment: string | null;
          created_at: string;
          created_by: string | null;
          decided_at: string;
          decided_by: string;
          decision: Database["workflow"]["Enums"]["decision"];
          deleted_at: string | null;
          deleted_by: string | null;
          id: string;
          request_id: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          comment?: string | null;
          created_at?: string;
          created_by?: string | null;
          decided_at?: string;
          decided_by: string;
          decision: Database["workflow"]["Enums"]["decision"];
          deleted_at?: string | null;
          deleted_by?: string | null;
          id?: string;
          request_id: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          comment?: string | null;
          created_at?: string;
          created_by?: string | null;
          decided_at?: string;
          decided_by?: string;
          decision?: Database["workflow"]["Enums"]["decision"];
          deleted_at?: string | null;
          deleted_by?: string | null;
          id?: string;
          request_id?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "approval_decisions_request_id_fkey";
            columns: ["request_id"];
            isOneToOne: false;
            referencedRelation: "approval_requests";
            referencedColumns: ["id"];
          },
        ];
      };
      approval_requests: {
        Row: {
          brand_id: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          payload: NonNullable<Json>;
          reason: string;
          requested_by: string;
          resolution_comment: string | null;
          resolved_at: string | null;
          resolved_by: string | null;
          restaurant_id: string | null;
          status: Database["workflow"]["Enums"]["request_status"];
          subject_user_id: string | null;
          updated_at: string;
          updated_by: string | null;
          workflow_id: string;
        };
        ComputedFields: never;
        Insert: {
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          payload: NonNullable<Json>;
          reason: string;
          requested_by: string;
          resolution_comment?: string | null;
          resolved_at?: string | null;
          resolved_by?: string | null;
          restaurant_id?: string | null;
          status?: Database["workflow"]["Enums"]["request_status"];
          subject_user_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          workflow_id: string;
        };
        Update: {
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          payload?: NonNullable<Json>;
          reason?: string;
          requested_by?: string;
          resolution_comment?: string | null;
          resolved_at?: string | null;
          resolved_by?: string | null;
          restaurant_id?: string | null;
          status?: Database["workflow"]["Enums"]["request_status"];
          subject_user_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          workflow_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "approval_requests_workflow_id_fkey";
            columns: ["workflow_id"];
            isOneToOne: false;
            referencedRelation: "approval_workflows";
            referencedColumns: ["id"];
          },
        ];
      };
      approval_workflows: {
        Row: {
          apply_function: unknown;
          approver_permission: string;
          approver_role_codes: string[] | null;
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          description: string | null;
          id: string;
          is_active: boolean;
          name: string;
          required_approvals: number;
          requires_different_approver: boolean;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          apply_function: unknown;
          approver_permission?: string;
          approver_role_codes?: string[] | null;
          code: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          id?: string;
          is_active?: boolean;
          name: string;
          required_approvals?: number;
          requires_different_approver?: boolean;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          apply_function?: unknown;
          approver_permission?: string;
          approver_role_codes?: string[] | null;
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          id?: string;
          is_active?: boolean;
          name?: string;
          required_approvals?: number;
          requires_different_approver?: boolean;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      cancel_request: { Args: { p_reason: string; p_request_id: string }; Returns: Json };
      create_request: {
        Args: {
          p_brand_id: string;
          p_group_id: string;
          p_payload: Json;
          p_reason: string;
          p_restaurant_id: string;
          p_subject_user_id: string;
          p_workflow_code: string;
        };
        Returns: string;
      };
      decide: {
        Args: { p_comment?: string; p_decision: string; p_request_id: string };
        Returns: Json;
      };
    };
    Enums: {
      decision: "approved" | "rejected";
      request_status: "pending" | "approved" | "rejected" | "cancelled";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema["Enums"] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema["CompositeTypes"] | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  audit: {
    Enums: {
      action: ["insert", "update", "soft_delete", "restore", "delete"],
      change_origin: ["app", "edge_function", "agent", "import", "seed", "maintenance"],
      security_event_type: [
        "login_succeeded",
        "login_failed",
        "account_locked",
        "account_unlocked",
        "operation_denied",
        "account_disabled",
        "account_reactivated",
      ],
    },
  },
  core: {
    Enums: {
      account_status: ["active", "disabled"],
      actor_type: ["user", "service_account"],
      scope_type: ["group", "brand", "restaurant"],
      version_status: ["draft", "in_review", "approved", "published", "archived"],
    },
  },
  org: {
    Enums: {
      unit_status: ["active", "inactive"],
    },
  },
  public: {
    Enums: {},
  },
  workflow: {
    Enums: {
      decision: ["approved", "rejected"],
      request_status: ["pending", "approved", "rejected", "cancelled"],
    },
  },
} as const;
