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
      actor_type: "user" | "service_account";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  org: {
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
      actor_type: ["user", "service_account"],
    },
  },
  org: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
  workflow: {
    Enums: {},
  },
} as const;
