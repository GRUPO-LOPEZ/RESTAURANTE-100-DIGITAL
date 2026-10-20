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
    };
    Enums: {
      action: "insert" | "update" | "soft_delete" | "restore" | "delete";
      change_origin: "app" | "edge_function" | "agent" | "import" | "seed" | "maintenance";
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
          first_name: string | null;
          id: string;
          last_name: string | null;
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
          first_name?: string | null;
          id: string;
          last_name?: string | null;
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
          first_name?: string | null;
          id?: string;
          last_name?: string | null;
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
      current_actor_id: { Args: Record<PropertyKey, never>; Returns: string };
      current_actor_subject: { Args: Record<PropertyKey, never>; Returns: string };
      set_change_context: { Args: { p_origin: string; p_reason: string }; Returns: undefined };
    };
    Enums: {
      account_status: "active" | "disabled";
      actor_type: "user" | "service_account";
      scope_type: "group" | "brand" | "restaurant";
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
          brand_id: string;
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
          brand_id: string;
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
          brand_id?: string;
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
        ];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      [_ in never]: never;
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
    },
  },
  core: {
    Enums: {
      account_status: ["active", "disabled"],
      actor_type: ["user", "service_account"],
      scope_type: ["group", "brand", "restaurant"],
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
    Enums: {},
  },
} as const;
