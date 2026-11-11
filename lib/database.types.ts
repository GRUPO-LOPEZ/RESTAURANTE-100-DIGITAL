export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  audit: {
    Tables: {
      audit_events: {
        Row: {
          action: Database["audit"]["Enums"]["action"];
          actor_role_code: string | null;
          actor_roles: Json | null;
          actor_service_account_id: string | null;
          actor_subject: string | null;
          actor_type: Database["core"]["Enums"]["actor_type"] | null;
          actor_user_id: string | null;
          changed_fields: string[] | null;
          db_user: string;
          id: string;
          jwt_role: string | null;
          module: string | null;
          new_values: Json | null;
          occurred_at: string;
          old_values: Json | null;
          operation_id: string | null;
          reason: string | null;
          record_id: string;
          scope_brand_id: string | null;
          scope_group_id: string | null;
          scope_restaurant_id: string | null;
          sequence_number: number;
          source: Database["audit"]["Enums"]["change_origin"] | null;
          status: string | null;
          table_name: string;
          table_schema: string;
          transaction_id: number;
          event_digest: string | null;
        };
        ComputedFields: "event_digest";
        Insert: {
          action: Database["audit"]["Enums"]["action"];
          actor_role_code?: string | null;
          actor_roles?: Json | null;
          actor_service_account_id?: string | null;
          actor_subject?: string | null;
          actor_type?: Database["core"]["Enums"]["actor_type"] | null;
          actor_user_id?: string | null;
          changed_fields?: string[] | null;
          db_user?: string;
          id?: string;
          jwt_role?: string | null;
          module?: string | null;
          new_values?: Json | null;
          occurred_at?: string;
          old_values?: Json | null;
          operation_id?: string | null;
          reason?: string | null;
          record_id: string;
          scope_brand_id?: string | null;
          scope_group_id?: string | null;
          scope_restaurant_id?: string | null;
          sequence_number?: never;
          source?: Database["audit"]["Enums"]["change_origin"] | null;
          status?: string | null;
          table_name: string;
          table_schema: string;
          transaction_id?: number;
        };
        Update: {
          action?: Database["audit"]["Enums"]["action"];
          actor_role_code?: string | null;
          actor_roles?: Json | null;
          actor_service_account_id?: string | null;
          actor_subject?: string | null;
          actor_type?: Database["core"]["Enums"]["actor_type"] | null;
          actor_user_id?: string | null;
          changed_fields?: string[] | null;
          db_user?: string;
          id?: string;
          jwt_role?: string | null;
          module?: string | null;
          new_values?: Json | null;
          occurred_at?: string;
          old_values?: Json | null;
          operation_id?: string | null;
          reason?: string | null;
          record_id?: string;
          scope_brand_id?: string | null;
          scope_group_id?: string | null;
          scope_restaurant_id?: string | null;
          sequence_number?: never;
          source?: Database["audit"]["Enums"]["change_origin"] | null;
          status?: string | null;
          table_name?: string;
          table_schema?: string;
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
      authentication_security_event_seals: {
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
      authentication_security_events: {
        Row: {
          actor_id: string | null;
          actor_subject: string | null;
          db_user: string;
          detail: Json | null;
          email: string | null;
          event_type: Database["audit"]["Enums"]["security_event_type"];
          id: string;
          ip_address: string | null;
          jwt_role: string | null;
          occurred_at: string;
          operation: string | null;
          reason: string | null;
          scope_brand_id: string | null;
          scope_group_id: string | null;
          scope_restaurant_id: string | null;
          sequence_number: number;
          user_agent: string | null;
          user_id: string | null;
          security_event_digest: string | null;
        };
        ComputedFields: "security_event_digest";
        Insert: {
          actor_id?: string | null;
          actor_subject?: string | null;
          db_user?: string;
          detail?: Json | null;
          email?: string | null;
          event_type: Database["audit"]["Enums"]["security_event_type"];
          id?: string;
          ip_address?: string | null;
          jwt_role?: string | null;
          occurred_at?: string;
          operation?: string | null;
          reason?: string | null;
          scope_brand_id?: string | null;
          scope_group_id?: string | null;
          scope_restaurant_id?: string | null;
          sequence_number?: never;
          user_agent?: string | null;
          user_id?: string | null;
        };
        Update: {
          actor_id?: string | null;
          actor_subject?: string | null;
          db_user?: string;
          detail?: Json | null;
          email?: string | null;
          event_type?: Database["audit"]["Enums"]["security_event_type"];
          id?: string;
          ip_address?: string | null;
          jwt_role?: string | null;
          occurred_at?: string;
          operation?: string | null;
          reason?: string | null;
          scope_brand_id?: string | null;
          scope_group_id?: string | null;
          scope_restaurant_id?: string | null;
          sequence_number?: never;
          user_agent?: string | null;
          user_id?: string | null;
        };
        Relationships: [];
      };
    };
    Views: {
      v_field_changes: {
        Row: {
          action: Database["audit"]["Enums"]["action"] | null;
          actor_role_code: string | null;
          actor_service_account_id: string | null;
          actor_user_id: string | null;
          event_id: string | null;
          field: string | null;
          module: string | null;
          new_value: Json | null;
          occurred_at: string | null;
          old_value: Json | null;
          operation_id: string | null;
          reason: string | null;
          record_id: string | null;
          scope_brand_id: string | null;
          scope_group_id: string | null;
          scope_restaurant_id: string | null;
          sequence_number: number | null;
          source: Database["audit"]["Enums"]["change_origin"] | null;
          table_name: string | null;
          table_schema: string | null;
        };
        ComputedFields: never;
        Relationships: [];
      };
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
      module_for: { Args: { p_schema: string; p_table: string }; Returns: string };
      redact: { Args: { p_excluded?: string[]; p_value: Json }; Returns: Json };
      row_digest: { Args: { p_row: Json }; Returns: string };
      seal_all: { Args: Record<PropertyKey, never>; Returns: Json };
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
          to: "authentication_security_event_seals";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      security_event_digest: {
        Args: {
          p_event: Omit<
            Database["audit"]["Tables"]["authentication_security_events"]["Row"],
            Database["audit"]["Tables"]["authentication_security_events"]["ComputedFields"]
          >;
        };
        Returns: string;
      };
      security_genesis_hash: { Args: Record<PropertyKey, never>; Returns: string };
      try_uuid: { Args: { p_value: string }; Returns: string };
      untracked_columns: { Args: { p_schema: string; p_table: string }; Returns: string[] };
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
      action:
        | "insert"
        | "update"
        | "soft_delete"
        | "restore"
        | "delete"
        | "approve"
        | "reject"
        | "publish";
      change_origin:
        | "manual"
        | "edge_function"
        | "agent"
        | "import"
        | "integration"
        | "seed"
        | "maintenance"
        | "auth";
      security_event_type:
        | "login_succeeded"
        | "login_failed"
        | "account_locked"
        | "account_unlocked"
        | "operation_denied"
        | "account_disabled"
        | "account_reactivated"
        | "account_suspended"
        | "account_unsuspended"
        | "password_changed"
        | "mfa_enrolled"
        | "audit_exported"
        | "report_exported";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  catalog: {
    Tables: {
      allergens: {
        Row: {
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          legal_reference: string | null;
          name: string;
          updated_at: string;
          updated_by: string | null;
          validated_at: string | null;
          validated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          code: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          legal_reference?: string | null;
          name: string;
          updated_at?: string;
          updated_by?: string | null;
          validated_at?: string | null;
          validated_by?: string | null;
        };
        Update: {
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          legal_reference?: string | null;
          name?: string;
          updated_at?: string;
          updated_by?: string | null;
          validated_at?: string | null;
          validated_by?: string | null;
        };
        Relationships: [];
      };
      ingredient_aliases: {
        Row: {
          alias: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          ingredient_id: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          alias: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          ingredient_id: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          alias?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          ingredient_id?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "ingredient_aliases_ingredient_fkey";
            columns: ["ingredient_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "ingredients";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      ingredient_allergens: {
        Row: {
          allergen_id: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          ingredient_id: string;
          notes: string | null;
          source: Database["catalog"]["Enums"]["data_source"];
          status: Database["catalog"]["Enums"]["allergen_status"];
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          allergen_id: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          ingredient_id: string;
          notes?: string | null;
          source: Database["catalog"]["Enums"]["data_source"];
          status: Database["catalog"]["Enums"]["allergen_status"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          allergen_id?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          ingredient_id?: string;
          notes?: string | null;
          source?: Database["catalog"]["Enums"]["data_source"];
          status?: Database["catalog"]["Enums"]["allergen_status"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "ingredient_allergens_allergen_fkey";
            columns: ["allergen_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "allergens";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "ingredient_allergens_ingredient_fkey";
            columns: ["ingredient_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "ingredients";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      ingredient_categories: {
        Row: {
          code: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          is_active: boolean;
          name: string;
          parent_id: string | null;
          stale_price_days: number | null;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          code?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          is_active?: boolean;
          name: string;
          parent_id?: string | null;
          stale_price_days?: number | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          code?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          is_active?: boolean;
          name?: string;
          parent_id?: string | null;
          stale_price_days?: number | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "ingredient_categories_parent_fkey";
            columns: ["parent_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "ingredient_categories";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      ingredient_unit_conversions: {
        Row: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          factor: number;
          group_id: string;
          id: string;
          ingredient_id: string;
          kind: Database["catalog"]["Enums"]["conversion_kind"];
          measured_by: string | null;
          measured_on: string;
          notes: string | null;
          source: Database["catalog"]["Enums"]["data_source"];
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          factor: number;
          group_id: string;
          id?: string;
          ingredient_id: string;
          kind: Database["catalog"]["Enums"]["conversion_kind"];
          measured_by?: string | null;
          measured_on: string;
          notes?: string | null;
          source: Database["catalog"]["Enums"]["data_source"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          factor?: number;
          group_id?: string;
          id?: string;
          ingredient_id?: string;
          kind?: Database["catalog"]["Enums"]["conversion_kind"];
          measured_by?: string | null;
          measured_on?: string;
          notes?: string | null;
          source?: Database["catalog"]["Enums"]["data_source"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "ingredient_unit_conversions_ingredient_fkey";
            columns: ["ingredient_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "ingredients";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      ingredient_yield_profiles: {
        Row: {
          approval_request_id: string | null;
          approved_at: string | null;
          approved_by: string | null;
          cleaning_yield: number;
          cooking_factor: number;
          created_at: string;
          created_by: string | null;
          cut: string | null;
          declared_no_loss: boolean;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          ingredient_id: string;
          method: string | null;
          notes: string | null;
          process_id: string;
          status: Database["catalog"]["Enums"]["yield_status"];
          supplier_id: string | null;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          approval_request_id?: string | null;
          approved_at?: string | null;
          approved_by?: string | null;
          cleaning_yield: number;
          cooking_factor: number;
          created_at?: string;
          created_by?: string | null;
          cut?: string | null;
          declared_no_loss?: boolean;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          ingredient_id: string;
          method?: string | null;
          notes?: string | null;
          process_id: string;
          status?: Database["catalog"]["Enums"]["yield_status"];
          supplier_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          approval_request_id?: string | null;
          approved_at?: string | null;
          approved_by?: string | null;
          cleaning_yield?: number;
          cooking_factor?: number;
          created_at?: string;
          created_by?: string | null;
          cut?: string | null;
          declared_no_loss?: boolean;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          ingredient_id?: string;
          method?: string | null;
          notes?: string | null;
          process_id?: string;
          status?: Database["catalog"]["Enums"]["yield_status"];
          supplier_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "ingredient_yield_profiles_ingredient_fkey";
            columns: ["ingredient_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "ingredients";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "ingredient_yield_profiles_process_fkey";
            columns: ["process_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "yield_processes";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "ingredient_yield_profiles_supplier_fkey";
            columns: ["supplier_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "suppliers";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      ingredient_yield_tests: {
        Row: {
          after_cooking_weight: number | null;
          before_cooking_weight: number | null;
          clean_weight: number | null;
          created_at: string;
          created_by: string | null;
          cut: string | null;
          discard_weight: number | null;
          gross_weight: number | null;
          group_id: string;
          id: string;
          ingredient_id: string;
          notes: string | null;
          process_id: string;
          responsible: string | null;
          restaurant_id: string;
          samples: number;
          supplier_id: string | null;
          tested_on: string;
        };
        ComputedFields: never;
        Insert: {
          after_cooking_weight?: number | null;
          before_cooking_weight?: number | null;
          clean_weight?: number | null;
          created_at?: string;
          created_by?: string | null;
          cut?: string | null;
          discard_weight?: number | null;
          gross_weight?: number | null;
          group_id: string;
          id?: string;
          ingredient_id: string;
          notes?: string | null;
          process_id: string;
          responsible?: string | null;
          restaurant_id: string;
          samples?: number;
          supplier_id?: string | null;
          tested_on: string;
        };
        Update: {
          after_cooking_weight?: number | null;
          before_cooking_weight?: number | null;
          clean_weight?: number | null;
          created_at?: string;
          created_by?: string | null;
          cut?: string | null;
          discard_weight?: number | null;
          gross_weight?: number | null;
          group_id?: string;
          id?: string;
          ingredient_id?: string;
          notes?: string | null;
          process_id?: string;
          responsible?: string | null;
          restaurant_id?: string;
          samples?: number;
          supplier_id?: string | null;
          tested_on?: string;
        };
        Relationships: [
          {
            foreignKeyName: "ingredient_yield_tests_ingredient_fkey";
            columns: ["ingredient_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "ingredients";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "ingredient_yield_tests_process_fkey";
            columns: ["process_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "yield_processes";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "ingredient_yield_tests_supplier_fkey";
            columns: ["supplier_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "suppliers";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      ingredients: {
        Row: {
          category_id: string;
          code: string;
          costing_unit_id: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          is_active: boolean;
          name: string;
          notes: string | null;
          purchase_unit_id: string | null;
          recipe_unit_id: string;
          requires_thawing: boolean;
          storage_unit_id: string | null;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          category_id: string;
          code: string;
          costing_unit_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          is_active?: boolean;
          name: string;
          notes?: string | null;
          purchase_unit_id?: string | null;
          recipe_unit_id: string;
          requires_thawing?: boolean;
          storage_unit_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          category_id?: string;
          code?: string;
          costing_unit_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          is_active?: boolean;
          name?: string;
          notes?: string | null;
          purchase_unit_id?: string | null;
          recipe_unit_id?: string;
          requires_thawing?: boolean;
          storage_unit_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "ingredients_category_fkey";
            columns: ["category_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "ingredient_categories";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "ingredients_costing_unit_id_fkey";
            columns: ["costing_unit_id"];
            isOneToOne: false;
            referencedRelation: "units";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "ingredients_purchase_unit_id_fkey";
            columns: ["purchase_unit_id"];
            isOneToOne: false;
            referencedRelation: "units";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "ingredients_recipe_unit_id_fkey";
            columns: ["recipe_unit_id"];
            isOneToOne: false;
            referencedRelation: "units";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "ingredients_storage_unit_id_fkey";
            columns: ["storage_unit_id"];
            isOneToOne: false;
            referencedRelation: "units";
            referencedColumns: ["id"];
          },
        ];
      };
      purchase_products: {
        Row: {
          brand_name: string | null;
          code: string;
          content_per_unit: number;
          content_unit_id: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          description: string;
          group_id: string;
          id: string;
          ingredient_id: string;
          is_active: boolean;
          notes: string | null;
          package_unit_id: string;
          supplier_id: string | null;
          units_per_package: number;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          brand_name?: string | null;
          code: string;
          content_per_unit: number;
          content_unit_id: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description: string;
          group_id: string;
          id?: string;
          ingredient_id: string;
          is_active?: boolean;
          notes?: string | null;
          package_unit_id: string;
          supplier_id?: string | null;
          units_per_package?: number;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          brand_name?: string | null;
          code?: string;
          content_per_unit?: number;
          content_unit_id?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string;
          group_id?: string;
          id?: string;
          ingredient_id?: string;
          is_active?: boolean;
          notes?: string | null;
          package_unit_id?: string;
          supplier_id?: string | null;
          units_per_package?: number;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "purchase_products_content_unit_id_fkey";
            columns: ["content_unit_id"];
            isOneToOne: false;
            referencedRelation: "units";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "purchase_products_ingredient_fkey";
            columns: ["ingredient_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "ingredients";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "purchase_products_package_unit_id_fkey";
            columns: ["package_unit_id"];
            isOneToOne: false;
            referencedRelation: "units";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "purchase_products_supplier_fkey";
            columns: ["supplier_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "suppliers";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      suppliers: {
        Row: {
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          is_active: boolean;
          is_internal: boolean;
          name: string;
          notes: string | null;
          tax_id: string | null;
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
          group_id: string;
          id?: string;
          is_active?: boolean;
          is_internal?: boolean;
          name: string;
          notes?: string | null;
          tax_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          is_active?: boolean;
          is_internal?: boolean;
          name?: string;
          notes?: string | null;
          tax_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [];
      };
      unit_conversions: {
        Row: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          factor: number;
          from_unit_id: string;
          id: string;
          to_unit_id: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          factor: number;
          from_unit_id: string;
          id?: string;
          to_unit_id: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          factor?: number;
          from_unit_id?: string;
          id?: string;
          to_unit_id?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "unit_conversions_from_unit_id_fkey";
            columns: ["from_unit_id"];
            isOneToOne: false;
            referencedRelation: "units";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "unit_conversions_to_unit_id_fkey";
            columns: ["to_unit_id"];
            isOneToOne: false;
            referencedRelation: "units";
            referencedColumns: ["id"];
          },
        ];
      };
      units: {
        Row: {
          abbreviation: string;
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          dimension: Database["catalog"]["Enums"]["dimension"];
          id: string;
          is_base: boolean;
          long_name: string;
          name: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          abbreviation: string;
          code: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          dimension: Database["catalog"]["Enums"]["dimension"];
          id?: string;
          is_base?: boolean;
          long_name: string;
          name: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          abbreviation?: string;
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          dimension?: Database["catalog"]["Enums"]["dimension"];
          id?: string;
          is_base?: boolean;
          long_name?: string;
          name?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [];
      };
      yield_processes: {
        Row: {
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          name: string;
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
          group_id: string;
          id?: string;
          name: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          name?: string;
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
      apply_requires_thawing: { Args: { p_request_id: string }; Returns: undefined };
      apply_yield_profile: { Args: { p_request_id: string }; Returns: undefined };
      approved_yield: {
        Args: {
          p_cut: string;
          p_ingredient_id: string;
          p_process_id: string;
          p_supplier_id: string;
        };
        Returns: {
          cleaning_yield: number;
          cooking_factor: number;
          declared_no_loss: boolean;
          profile_id: string;
        }[];
      };
      archive_category: { Args: { p_id: string; p_reason: string }; Returns: undefined };
      archive_unit: {
        Args: { p_group_id: string; p_reason: string; p_unit_id: string };
        Returns: undefined;
      };
      archive_yield_process: { Args: { p_id: string; p_reason: string }; Returns: undefined };
      category_first_word: { Args: { p_name: string }; Returns: string };
      category_group: { Args: { p_category_id: string }; Returns: string };
      category_match_name: { Args: { p_name: string }; Returns: string };
      category_usage: {
        Args: Record<PropertyKey, never>;
        Returns: {
          category_id: string;
          ingredients: number;
        }[];
      };
      check_ingredient_products: {
        Args: { p_action: string; p_ingredient_id: string };
        Returns: undefined;
      };
      convert_quantity: {
        Args: {
          p_from_unit_id: string;
          p_ingredient_id: string;
          p_quantity: number;
          p_to_unit_id: string;
        };
        Returns: {
          quantity: number;
          status: string;
        }[];
      };
      costing_yield: {
        Args: {
          p_cut: string;
          p_ingredient_id: string;
          p_process_id: string;
          p_supplier_id: string;
        };
        Returns: {
          cleaning_yield: number;
          cooking_factor: number;
          profile_id: string;
          thawing_yield: number;
        }[];
      };
      create_category: {
        Args: { p_group_id: string; p_name: string; p_parent_id?: string; p_reason: string };
        Returns: string;
      };
      create_ingredient: {
        Args: {
          p_category_id: string;
          p_code: string;
          p_details: Json;
          p_group_id: string;
          p_name: string;
          p_reason: string;
          p_recipe_unit: string;
        };
        Returns: string;
      };
      create_purchase_product: {
        Args: {
          p_code: string;
          p_content_per_unit: number;
          p_content_unit: string;
          p_description: string;
          p_details: Json;
          p_ingredient_id: string;
          p_package_unit: string;
          p_reason: string;
          p_units_per_package: number;
        };
        Returns: string;
      };
      create_supplier: {
        Args: {
          p_code: string;
          p_details: Json;
          p_group_id: string;
          p_name: string;
          p_reason: string;
        };
        Returns: string;
      };
      create_unit: {
        Args: {
          p_abbreviation: string;
          p_code: string;
          p_dimension: Database["catalog"]["Enums"]["dimension"];
          p_factor?: number;
          p_group_id: string;
          p_long_name: string;
          p_reason: string;
        };
        Returns: string;
      };
      create_yield_process: {
        Args: { p_code: string; p_group_id: string; p_name: string; p_reason: string };
        Returns: string;
      };
      free_category_code: {
        Args: { p_name: string; p_prefix: string; p_taken: string[] };
        Returns: string;
      };
      group_yield_alert_pct: { Args: { p_group_id: string }; Returns: number };
      ingredient_group: { Args: { p_ingredient_id: string }; Returns: string };
      ingredient_usage: {
        Args: { p_ingredient_id: string };
        Returns: {
          code: string;
          name: string;
          recipe_id: string;
          status: Database["core"]["Enums"]["version_status"];
          version_number: number;
        }[];
      };
      missing_conversion: {
        Args: { p_content_unit_id: string; p_ingredient_id: string };
        Returns: string;
      };
      notify_yield_deviation: { Args: { p_test_id: string }; Returns: undefined };
      process_usage: {
        Args: Record<PropertyKey, never>;
        Returns: {
          process_id: string;
          standards: number;
        }[];
      };
      propose_waste: {
        Args: {
          p_cleaning_loss?: number;
          p_declared_no_loss: boolean;
          p_ingredient_id: string;
          p_method: string;
          p_reason: string;
          p_thawing_loss?: number;
        };
        Returns: Json;
      };
      propose_yield_standard: {
        Args: {
          p_cleaning_yield: number;
          p_cooking_factor: number;
          p_cut: string;
          p_declared_no_loss: boolean;
          p_ingredient_id: string;
          p_method: string;
          p_process_id: string;
          p_reason: string;
          p_supplier_id?: string;
        };
        Returns: string;
      };
      raise_friendly: {
        Args: { p_constraint: string; p_message: string; p_state: string };
        Returns: undefined;
      };
      record_yield_test: {
        Args: {
          p_details: Json;
          p_ingredient_id: string;
          p_measures: Json;
          p_process_id: string;
          p_reason: string;
          p_restaurant_id: string;
          p_tested_on: string;
        };
        Returns: string;
      };
      rename_category: {
        Args: { p_id: string; p_name: string; p_reason: string };
        Returns: undefined;
      };
      rename_yield_process: {
        Args: { p_id: string; p_name: string; p_reason: string };
        Returns: undefined;
      };
      require_name: { Args: { p_name: string }; Returns: undefined };
      search_components: {
        Args: { p_limit?: number; p_query: string };
        Returns: {
          code: string;
          id: string;
          kind: string;
          matched: string;
          name: string;
          score: number;
          unit: string;
        }[];
      };
      set_aliases: {
        Args: { p_aliases: string[]; p_ingredient_id: string; p_reason: string };
        Returns: undefined;
      };
      set_allergen_status: {
        Args: {
          p_allergen_id: string;
          p_ingredient_id: string;
          p_reason: string;
          p_source: Database["catalog"]["Enums"]["data_source"];
          p_status: Database["catalog"]["Enums"]["allergen_status"];
        };
        Returns: undefined;
      };
      set_category_stale_days: {
        Args: { p_category_id: string; p_days: number; p_reason: string };
        Returns: undefined;
      };
      set_ingredient_active: {
        Args: { p_active: boolean; p_id: string; p_reason: string };
        Returns: undefined;
      };
      set_requires_thawing: {
        Args: { p_ingredient_id: string; p_reason: string; p_value: boolean };
        Returns: Json;
      };
      set_unit_conversion: {
        Args: {
          p_factor: number;
          p_ingredient_id: string;
          p_kind: Database["catalog"]["Enums"]["conversion_kind"];
          p_measured_by: string;
          p_measured_on: string;
          p_reason: string;
          p_source: Database["catalog"]["Enums"]["data_source"];
        };
        Returns: undefined;
      };
      standard_yield: {
        Args: {
          p_cut?: string;
          p_ingredient_id: string;
          p_process_id: string;
          p_supplier_id?: string;
        };
        Returns: {
          cleaning_yield: number;
          cooking_factor: number;
          declared_no_loss: boolean;
          profile_id: string;
          status: string;
        }[];
      };
      thawing_change_pending: { Args: { p_ingredient_id: string }; Returns: boolean };
      thawing_factor: {
        Args: { p_ingredient_id: string; p_process_id: string; p_supplier_id: string };
        Returns: number;
      };
      to_base_quantity: {
        Args: { p_ingredient_id: string; p_quantity: number; p_unit_id: string };
        Returns: {
          base_quantity: number;
          base_unit: string;
          status: string;
        }[];
      };
      unit_id: { Args: { p_code: string }; Returns: string };
      unit_in_use: { Args: { p_unit_id: string }; Returns: boolean };
      update_ingredient: {
        Args: { p_changes: Json; p_id: string; p_reason: string };
        Returns: undefined;
      };
      update_purchase_product: {
        Args: { p_changes: Json; p_id: string; p_reason: string };
        Returns: undefined;
      };
      update_supplier: {
        Args: { p_changes: Json; p_id: string; p_reason: string };
        Returns: undefined;
      };
      yield_alert_threshold: { Args: { p_ingredient_id: string }; Returns: number };
      yield_deviation: {
        Args: { p_test_id: string };
        Returns: {
          cleaning_pct: number;
          cooking_pct: number;
          measured_cleaning: number;
          measured_cooking: number;
          standard_cleaning: number;
          standard_cooking: number;
        }[];
      };
      yield_process_group: { Args: { p_process_id: string }; Returns: string };
      yield_summary: {
        Args: { p_ingredient_id: string };
        Returns: {
          approved_at: string;
          cut: string;
          declared_no_loss: boolean;
          last_tested_on: string;
          measured_cleaning: number;
          measured_cooking: number;
          pending_proposals: number;
          process_id: string;
          process_name: string;
          standard_cleaning: number;
          standard_cooking: number;
          supplier_id: string;
          supplier_name: string;
          tests: number;
        }[];
      };
    };
    Enums: {
      allergen_status: "contains" | "may_contain" | "free_verified";
      conversion_kind: "density" | "unit_weight";
      data_source:
        | "manual"
        | "excel_import"
        | "measured"
        | "supplier"
        | "calculated"
        | "estimated"
        | "verified";
      dimension: "mass" | "volume" | "count" | "package";
      yield_status: "draft" | "approved" | "superseded";
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
      login_throttles: {
        Row: {
          email: string;
          failed_count: number;
          last_failed_at: string | null;
          locked_until: string | null;
          updated_at: string;
          window_started_at: string | null;
        };
        ComputedFields: never;
        Insert: {
          email: string;
          failed_count?: number;
          last_failed_at?: string | null;
          locked_until?: string | null;
          updated_at?: string;
          window_started_at?: string | null;
        };
        Update: {
          email?: string;
          failed_count?: number;
          last_failed_at?: string | null;
          locked_until?: string | null;
          updated_at?: string;
          window_started_at?: string | null;
        };
        Relationships: [];
      };
      notifications: {
        Row: {
          body: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          kind: Database["core"]["Enums"]["notification_kind"];
          link: string | null;
          read_at: string | null;
          recipient_user_id: string;
          request_id: string | null;
          title: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          body?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          kind: Database["core"]["Enums"]["notification_kind"];
          link?: string | null;
          read_at?: string | null;
          recipient_user_id: string;
          request_id?: string | null;
          title: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          body?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          kind?: Database["core"]["Enums"]["notification_kind"];
          link?: string | null;
          read_at?: string | null;
          recipient_user_id?: string;
          request_id?: string | null;
          title?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "notifications_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "notifications_deleted_by_fkey";
            columns: ["deleted_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "notifications_recipient_user_id_fkey";
            columns: ["recipient_user_id"];
            isOneToOne: false;
            referencedRelation: "user_profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "notifications_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
        ];
      };
      permission_modules: {
        Row: {
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          id: string;
          name: string;
          sort_order: number;
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
          id?: string;
          name: string;
          sort_order?: number;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          id?: string;
          name?: string;
          sort_order?: number;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "permission_modules_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "permission_modules_deleted_by_fkey";
            columns: ["deleted_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "permission_modules_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
        ];
      };
      permissions: {
        Row: {
          action: string;
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          description: string;
          id: string;
          is_sensitive: boolean;
          module: string;
          name: string | null;
          sort_order: number;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          action: string;
          code: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description: string;
          id?: string;
          is_sensitive?: boolean;
          module: string;
          name?: string | null;
          sort_order?: number;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          action?: string;
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string;
          id?: string;
          is_sensitive?: boolean;
          module?: string;
          name?: string | null;
          sort_order?: number;
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
          brand_id: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          ends_at: string | null;
          group_id: string;
          id: string;
          restaurant_id: string | null;
          starts_at: string;
          updated_at: string;
          updated_by: string | null;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          ends_at?: string | null;
          group_id: string;
          id?: string;
          restaurant_id?: string | null;
          starts_at?: string;
          updated_at?: string;
          updated_by?: string | null;
          user_id: string;
        };
        Update: {
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          ends_at?: string | null;
          group_id?: string;
          id?: string;
          restaurant_id?: string | null;
          starts_at?: string;
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
          activated_at: string | null;
          area_id: string | null;
          created_at: string;
          created_by: string | null;
          deactivated_at: string | null;
          deactivated_by: string | null;
          deactivation_reason: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          email: string;
          first_name: string | null;
          id: string;
          invited_by: string | null;
          job_title: string | null;
          last_name: string | null;
          last_restaurant_id: string | null;
          last_seen_at: string | null;
          locked_until: string | null;
          status: Database["core"]["Enums"]["account_status"];
          suspended_at: string | null;
          suspended_by: string | null;
          suspension_reason: string | null;
          updated_at: string;
          updated_by: string | null;
          username: string | null;
        };
        ComputedFields: never;
        Insert: {
          activated_at?: string | null;
          area_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deactivated_at?: string | null;
          deactivated_by?: string | null;
          deactivation_reason?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          email: string;
          first_name?: string | null;
          id: string;
          invited_by?: string | null;
          job_title?: string | null;
          last_name?: string | null;
          last_restaurant_id?: string | null;
          last_seen_at?: string | null;
          locked_until?: string | null;
          status?: Database["core"]["Enums"]["account_status"];
          suspended_at?: string | null;
          suspended_by?: string | null;
          suspension_reason?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          username?: string | null;
        };
        Update: {
          activated_at?: string | null;
          area_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deactivated_at?: string | null;
          deactivated_by?: string | null;
          deactivation_reason?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          email?: string;
          first_name?: string | null;
          id?: string;
          invited_by?: string | null;
          job_title?: string | null;
          last_name?: string | null;
          last_restaurant_id?: string | null;
          last_seen_at?: string | null;
          locked_until?: string | null;
          status?: Database["core"]["Enums"]["account_status"];
          suspended_at?: string | null;
          suspended_by?: string | null;
          suspension_reason?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          username?: string | null;
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
            foreignKeyName: "user_profiles_deactivated_by_fkey";
            columns: ["deactivated_by"];
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
            foreignKeyName: "user_profiles_invited_by_fkey";
            columns: ["invited_by"];
            isOneToOne: false;
            referencedRelation: "actors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "user_profiles_suspended_by_fkey";
            columns: ["suspended_by"];
            isOneToOne: false;
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
      add_member: {
        Args: {
          p_brand_id?: string;
          p_group_id: string;
          p_reason: string;
          p_restaurant_id?: string;
          p_user_id: string;
        };
        Returns: Json;
      };
      apply_governance_status: { Args: { p_request_id: string }; Returns: undefined };
      apply_permission_matrix: {
        Args: { p_changes: Json; p_group_id: string; p_reason: string };
        Returns: Json;
      };
      apply_reactivation: { Args: { p_request_id: string }; Returns: undefined };
      apply_role_assignment: { Args: { p_request_id: string }; Returns: undefined };
      apply_role_permission_change: { Args: { p_request_id: string }; Returns: undefined };
      apply_role_revocation: { Args: { p_request_id: string }; Returns: undefined };
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
      assignment_unit_open: {
        Args: { p_brand_id: string; p_restaurant_id: string };
        Returns: boolean;
      };
      audit_export: {
        Args: {
          p_actor_id?: string;
          p_brand_id?: string;
          p_from?: string;
          p_limit?: number;
          p_module?: string;
          p_record_id?: string;
          p_restaurant_id?: string;
          p_to?: string;
        };
        Returns: {
          action: string;
          actor_name: string;
          actor_role_code: string;
          field: string;
          module: string;
          new_value: string;
          occurred_at: string;
          old_value: string;
          operation_id: string;
          place_name: string;
          reason: string;
          record_id: string;
          source: string;
          table_name: string;
        }[];
      };
      audit_history: {
        Args: {
          p_actor_id?: string;
          p_before?: number;
          p_brand_id?: string;
          p_critical_only?: boolean;
          p_from?: string;
          p_limit?: number;
          p_module?: string;
          p_record_id?: string;
          p_restaurant_id?: string;
          p_to?: string;
        };
        Returns: {
          action: string;
          actor_name: string;
          actor_role_code: string;
          changed_fields: string[];
          module: string;
          new_values: Json;
          occurred_at: string;
          old_values: Json;
          place_name: string;
          reason: string;
          record_id: string;
          sequence_number: number;
          source: string;
          table_name: string;
          table_schema: string;
        }[];
      };
      audit_scope_events: {
        Args: {
          p_actor_id: string;
          p_after: number;
          p_before: number;
          p_bids: string[];
          p_from: string;
          p_gids: string[];
          p_limit: number;
          p_module: string;
          p_record_id: string;
          p_rids: string[];
          p_tables: string[];
          p_to: string;
        };
        Returns: Database["audit"]["Tables"]["audit_events"]["Row"][];
        SetofOptions: {
          from: "*";
          to: "audit_events";
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      audit_sequence_bounds: {
        Args: { p_from: string; p_to: string };
        Returns: Record<string, unknown>;
      };
      can_administer_user: { Args: { p_user_id: string }; Returns: boolean };
      can_invite: {
        Args: {
          p_brand_id?: string;
          p_email?: string;
          p_group_id: string;
          p_restaurant_id?: string;
          p_scope_type: Database["core"]["Enums"]["scope_type"];
        };
        Returns: Json;
      };
      can_see_costs: {
        Args: { p_brand_id: string; p_group_id: string; p_restaurant_id: string };
        Returns: boolean;
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
      cannot_act_on_user: { Args: { p_permission: string; p_user_id: string }; Returns: string };
      check_person_separation: {
        Args: { p_group_id: string; p_role_id: string; p_user_id: string };
        Returns: undefined;
      };
      check_role_permission_change: {
        Args: { p_grant: boolean; p_permission_code: string; p_role_id: string };
        Returns: undefined;
      };
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
      custom_access_token_hook: { Args: { event: Json }; Returns: Json };
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
      disable_user: { Args: { p_reason: string; p_user_id: string }; Returns: Json };
      display_name: { Args: { p_user_id: string }; Returns: string };
      governance_workflow: { Args: { p_action: string; p_user_id: string }; Returns: string };
      group_governance_gap: {
        Args: { p_group_id: string; p_without_assignment: string; p_without_user: string };
        Returns: string;
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
      has_permission_in_group_any_scope: {
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
      hide_costs: { Args: { p_value: Json }; Returns: Json };
      holds_group_role: {
        Args: { p_group_id: string; p_role_code: string; p_user_id: string };
        Returns: boolean;
      };
      is_assignment_current: {
        Args: { p_valid_from: string; p_valid_until: string };
        Returns: boolean;
      };
      is_sensitive_role: { Args: { p_role_id: string }; Returns: boolean };
      lift_suspension: { Args: { p_reason: string; p_user_id: string }; Returns: Json };
      lock_group_roles: { Args: { p_group_id: string }; Returns: undefined };
      login_status: { Args: { p_email: string }; Returns: Json };
      mark_notifications_read: { Args: { p_ids?: string[] }; Returns: number };
      membership_covers: {
        Args: {
          p_brand_id?: string;
          p_except_membership_id?: string;
          p_group_id: string;
          p_restaurant_id?: string;
          p_scope_type: Database["core"]["Enums"]["scope_type"];
          p_user_id: string;
        };
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
      my_account: { Args: Record<PropertyKey, never>; Returns: Json };
      my_active_restaurant: { Args: Record<PropertyKey, never>; Returns: string };
      my_scopes: {
        Args: Record<PropertyKey, never>;
        Returns: {
          brand_code: string;
          brand_id: string;
          brand_name: string;
          restaurant_code: string;
          restaurant_id: string;
          restaurant_name: string;
        }[];
      };
      my_session: { Args: Record<PropertyKey, never>; Returns: Json };
      permission_matrix: { Args: { p_group_id: string }; Returns: Json };
      permitted_brand_ids: { Args: { p_permission: string }; Returns: string[] };
      permitted_group_ids: { Args: { p_permission: string }; Returns: string[] };
      permitted_restaurant_ids: { Args: { p_permission: string }; Returns: string[] };
      record_failed_login: {
        Args: { p_email: string; p_ip?: string; p_user_agent?: string };
        Returns: Json;
      };
      request_governance_status: {
        Args: { p_action: string; p_reason: string; p_user_id: string };
        Returns: Json;
      };
      request_reactivation: { Args: { p_reason: string; p_user_id: string }; Returns: Json };
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
      role_holders: { Args: { p_role_id: string }; Returns: Json };
      role_permission_codes: { Args: { p_role_id: string }; Returns: string[] };
      set_active_restaurant: { Args: { p_restaurant_id?: string }; Returns: Json };
      set_change_context: { Args: { p_origin: string; p_reason: string }; Returns: undefined };
      suspend_user: { Args: { p_reason: string; p_user_id: string }; Returns: Json };
      unlock_user: { Args: { p_reason: string; p_user_id: string }; Returns: Json };
      update_my_profile: { Args: { p_first_name: string; p_last_name: string }; Returns: Json };
      user_detail: { Args: { p_user_id: string }; Returns: Json };
      user_group: { Args: { p_user_id: string }; Returns: string };
      user_has_permission_for_scope: {
        Args: {
          p_brand_id?: string;
          p_group_id: string;
          p_permission: string;
          p_restaurant_id?: string;
          p_scope_type: Database["core"]["Enums"]["scope_type"];
          p_user_id: string;
        };
        Returns: boolean;
      };
      user_has_role_for_scope: {
        Args: {
          p_brand_id?: string;
          p_group_id: string;
          p_restaurant_id?: string;
          p_role_codes: string[];
          p_scope_type: Database["core"]["Enums"]["scope_type"];
          p_user_id: string;
        };
        Returns: boolean;
      };
      user_missing_permissions_for_role: {
        Args: {
          p_brand_id: string;
          p_group_id: string;
          p_restaurant_id: string;
          p_role_id: string;
          p_scope_type: Database["core"]["Enums"]["scope_type"];
          p_user_id: string;
        };
        Returns: string[];
      };
      users_control_panel: {
        Args: {
          p_brand_id?: string;
          p_from?: string;
          p_module?: string;
          p_restaurant_id?: string;
          p_to?: string;
        };
        Returns: Json;
      };
      users_dashboard: {
        Args: {
          p_after_id?: string;
          p_after_key?: string;
          p_area_id?: string;
          p_brand_id?: string;
          p_limit?: number;
          p_restaurant_id?: string;
          p_role_code?: string;
          p_search?: string;
          p_status?: string;
          p_user_id?: string;
        };
        Returns: {
          area_name: string;
          email: string;
          first_name: string;
          id: string;
          job_title: string;
          last_name: string;
          last_seen_at: string;
          locked: boolean;
          roles: Json;
          sort_key: string;
          status: Database["core"]["Enums"]["account_status"];
        }[];
      };
      users_overview: { Args: { p_brand_id?: string; p_restaurant_id?: string }; Returns: Json };
      visible_assignment_ids: { Args: Record<PropertyKey, never>; Returns: string[] };
      visible_brand_ids: { Args: { p_permission: string }; Returns: string[] };
      visible_group_ids: { Args: { p_permission: string }; Returns: string[] };
      visible_user_ids: { Args: Record<PropertyKey, never>; Returns: string[] };
    };
    Enums: {
      account_status: "active" | "suspended" | "deactivated";
      actor_type: "user" | "service_account";
      notification_kind:
        "approval_requested" | "recipe_changed" | "recipe_cost_changed" | "yield_deviation";
      scope_type: "group" | "brand" | "restaurant";
      version_status: "draft" | "in_review" | "approved" | "published" | "archived";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  costing: {
    Tables: {
      cost_recalc_queue: {
        Row: {
          attempts: number;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          entry_number: number;
          error: string | null;
          group_id: string;
          id: string;
          price_record_id: string | null;
          processed_at: string | null;
          reason: Database["costing"]["Enums"]["cost_snapshot_reason"];
          recipe_ids: string[];
          restaurant_ids: string[] | null;
          source_recipe_id: string | null;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          attempts?: number;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          entry_number?: never;
          error?: string | null;
          group_id: string;
          id?: string;
          price_record_id?: string | null;
          processed_at?: string | null;
          reason: Database["costing"]["Enums"]["cost_snapshot_reason"];
          recipe_ids: string[];
          restaurant_ids?: string[] | null;
          source_recipe_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          attempts?: number;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          entry_number?: never;
          error?: string | null;
          group_id?: string;
          id?: string;
          price_record_id?: string | null;
          processed_at?: string | null;
          reason?: Database["costing"]["Enums"]["cost_snapshot_reason"];
          recipe_ids?: string[];
          restaurant_ids?: string[] | null;
          source_recipe_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "cost_recalc_queue_price_record_id_fkey";
            columns: ["price_record_id"];
            isOneToOne: false;
            referencedRelation: "price_records";
            referencedColumns: ["id"];
          },
        ];
      };
      cost_scenario_overrides: {
        Row: {
          cleaning_yield: number | null;
          cooking_factor: number | null;
          created_at: string;
          created_by: string | null;
          currency: string;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          ingredient_id: string | null;
          kind: Database["costing"]["Enums"]["scenario_override_kind"];
          quantity: number | null;
          recipe_component_id: string | null;
          restaurant_id: string;
          scenario_id: string;
          supplier_id: string | null;
          unit_cost: number | null;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          cleaning_yield?: number | null;
          cooking_factor?: number | null;
          created_at?: string;
          created_by?: string | null;
          currency?: string;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          ingredient_id?: string | null;
          kind: Database["costing"]["Enums"]["scenario_override_kind"];
          quantity?: number | null;
          recipe_component_id?: string | null;
          restaurant_id: string;
          scenario_id: string;
          supplier_id?: string | null;
          unit_cost?: number | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          cleaning_yield?: number | null;
          cooking_factor?: number | null;
          created_at?: string;
          created_by?: string | null;
          currency?: string;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          ingredient_id?: string | null;
          kind?: Database["costing"]["Enums"]["scenario_override_kind"];
          quantity?: number | null;
          recipe_component_id?: string | null;
          restaurant_id?: string;
          scenario_id?: string;
          supplier_id?: string | null;
          unit_cost?: number | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "cost_scenario_overrides_scenario_fkey";
            columns: ["scenario_id", "restaurant_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "cost_scenarios";
            referencedColumns: ["id", "restaurant_id", "group_id"];
          },
        ];
      };
      cost_scenarios: {
        Row: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          name: string;
          restaurant_id: string;
          status: Database["costing"]["Enums"]["scenario_status"];
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
          status?: Database["costing"]["Enums"]["scenario_status"];
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
          status?: Database["costing"]["Enums"]["scenario_status"];
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [];
      };
      price_records: {
        Row: {
          approval_request_id: string | null;
          approved_at: string | null;
          approved_by: string | null;
          base_quantity: number;
          brand_id: string | null;
          created_at: string;
          created_by: string | null;
          currency: string;
          deleted_at: string | null;
          deleted_by: string | null;
          discount_amount: number;
          document_type: Database["costing"]["Enums"]["price_document"];
          entry_number: number;
          gross_package_price: number;
          group_id: string;
          id: string;
          net_package_price: number;
          notes: string | null;
          package_price: number;
          price_includes_vat: boolean;
          purchase_product_id: string;
          restaurant_id: string | null;
          scope_type: Database["core"]["Enums"]["scope_type"];
          source: Database["costing"]["Enums"]["price_source"];
          supplier_id: string | null;
          updated_at: string;
          updated_by: string | null;
          valid_from: string;
          vat_rate: number | null;
        };
        ComputedFields: never;
        Insert: {
          approval_request_id?: string | null;
          approved_at?: string | null;
          approved_by?: string | null;
          base_quantity: number;
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          currency?: string;
          deleted_at?: string | null;
          deleted_by?: string | null;
          discount_amount?: number;
          document_type: Database["costing"]["Enums"]["price_document"];
          entry_number?: never;
          gross_package_price: number;
          group_id: string;
          id?: string;
          net_package_price: number;
          notes?: string | null;
          package_price: number;
          price_includes_vat?: boolean;
          purchase_product_id: string;
          restaurant_id?: string | null;
          scope_type: Database["core"]["Enums"]["scope_type"];
          source: Database["costing"]["Enums"]["price_source"];
          supplier_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          valid_from: string;
          vat_rate?: number | null;
        };
        Update: {
          approval_request_id?: string | null;
          approved_at?: string | null;
          approved_by?: string | null;
          base_quantity?: number;
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          currency?: string;
          deleted_at?: string | null;
          deleted_by?: string | null;
          discount_amount?: number;
          document_type?: Database["costing"]["Enums"]["price_document"];
          entry_number?: never;
          gross_package_price?: number;
          group_id?: string;
          id?: string;
          net_package_price?: number;
          notes?: string | null;
          package_price?: number;
          price_includes_vat?: boolean;
          purchase_product_id?: string;
          restaurant_id?: string | null;
          scope_type?: Database["core"]["Enums"]["scope_type"];
          source?: Database["costing"]["Enums"]["price_source"];
          supplier_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          valid_from?: string;
          vat_rate?: number | null;
        };
        Relationships: [];
      };
      price_settings: {
        Row: {
          approval_variation_pct: number;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          lookback_days: number;
          stale_days: number;
          updated_at: string;
          updated_by: string | null;
          yield_alert_pct: number;
        };
        ComputedFields: never;
        Insert: {
          approval_variation_pct?: number;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          lookback_days?: number;
          stale_days?: number;
          updated_at?: string;
          updated_by?: string | null;
          yield_alert_pct?: number;
        };
        Update: {
          approval_variation_pct?: number;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          lookback_days?: number;
          stale_days?: number;
          updated_at?: string;
          updated_by?: string | null;
          yield_alert_pct?: number;
        };
        Relationships: [];
      };
      recipe_cost_current: {
        Row: {
          as_of: string;
          cost_per_base_unit: number | null;
          cost_per_portion: number | null;
          created_at: string;
          created_by: string | null;
          currency: string;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          method_version: number;
          recipe_id: string;
          recipe_version_id: string;
          reliability: Database["costing"]["Enums"]["cost_reliability"];
          restaurant_id: string;
          total_cost: number | null;
          total_gross_cost: number | null;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          as_of: string;
          cost_per_base_unit?: number | null;
          cost_per_portion?: number | null;
          created_at?: string;
          created_by?: string | null;
          currency?: string;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          method_version?: number;
          recipe_id: string;
          recipe_version_id: string;
          reliability: Database["costing"]["Enums"]["cost_reliability"];
          restaurant_id: string;
          total_cost?: number | null;
          total_gross_cost?: number | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          as_of?: string;
          cost_per_base_unit?: number | null;
          cost_per_portion?: number | null;
          created_at?: string;
          created_by?: string | null;
          currency?: string;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          method_version?: number;
          recipe_id?: string;
          recipe_version_id?: string;
          reliability?: Database["costing"]["Enums"]["cost_reliability"];
          restaurant_id?: string;
          total_cost?: number | null;
          total_gross_cost?: number | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [];
      };
      recipe_cost_snapshot_lines: {
        Row: {
          base_quantity: number | null;
          cleaning_yield: number | null;
          cooking_factor: number | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          gross_unit_cost: number | null;
          group_id: string;
          id: string;
          ingredient_id: string | null;
          item: string;
          line_cost: number | null;
          line_gross_cost: number | null;
          line_order: number;
          line_status: string;
          package_base_quantity: number | null;
          price_level: Database["core"]["Enums"]["scope_type"] | null;
          price_record_id: string | null;
          purchase_quantity: number | null;
          quantity: number;
          quantity_basis: Database["recipes"]["Enums"]["quantity_basis"];
          recipe_version_id: string;
          restaurant_id: string;
          share_pct: number | null;
          snapshot_id: string;
          sub_recipe_id: string | null;
          sub_recipe_version_id: string | null;
          unit_cost: number | null;
          unit_id: string;
          updated_at: string;
          updated_by: string | null;
          vat_condition: Database["org"]["Enums"]["vat_condition"] | null;
          yield_profile_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          base_quantity?: number | null;
          cleaning_yield?: number | null;
          cooking_factor?: number | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          gross_unit_cost?: number | null;
          group_id: string;
          id?: string;
          ingredient_id?: string | null;
          item: string;
          line_cost?: number | null;
          line_gross_cost?: number | null;
          line_order: number;
          line_status: string;
          package_base_quantity?: number | null;
          price_level?: Database["core"]["Enums"]["scope_type"] | null;
          price_record_id?: string | null;
          purchase_quantity?: number | null;
          quantity: number;
          quantity_basis: Database["recipes"]["Enums"]["quantity_basis"];
          recipe_version_id: string;
          restaurant_id: string;
          share_pct?: number | null;
          snapshot_id: string;
          sub_recipe_id?: string | null;
          sub_recipe_version_id?: string | null;
          unit_cost?: number | null;
          unit_id: string;
          updated_at?: string;
          updated_by?: string | null;
          vat_condition?: Database["org"]["Enums"]["vat_condition"] | null;
          yield_profile_id?: string | null;
        };
        Update: {
          base_quantity?: number | null;
          cleaning_yield?: number | null;
          cooking_factor?: number | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          gross_unit_cost?: number | null;
          group_id?: string;
          id?: string;
          ingredient_id?: string | null;
          item?: string;
          line_cost?: number | null;
          line_gross_cost?: number | null;
          line_order?: number;
          line_status?: string;
          package_base_quantity?: number | null;
          price_level?: Database["core"]["Enums"]["scope_type"] | null;
          price_record_id?: string | null;
          purchase_quantity?: number | null;
          quantity?: number;
          quantity_basis?: Database["recipes"]["Enums"]["quantity_basis"];
          recipe_version_id?: string;
          restaurant_id?: string;
          share_pct?: number | null;
          snapshot_id?: string;
          sub_recipe_id?: string | null;
          sub_recipe_version_id?: string | null;
          unit_cost?: number | null;
          unit_id?: string;
          updated_at?: string;
          updated_by?: string | null;
          vat_condition?: Database["org"]["Enums"]["vat_condition"] | null;
          yield_profile_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "recipe_cost_snapshot_lines_price_record_id_fkey";
            columns: ["price_record_id"];
            isOneToOne: false;
            referencedRelation: "price_records";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "recipe_cost_snapshot_lines_snapshot_id_fkey";
            columns: ["snapshot_id"];
            isOneToOne: false;
            referencedRelation: "recipe_cost_snapshots";
            referencedColumns: ["id"];
          },
        ];
      };
      recipe_cost_snapshots: {
        Row: {
          as_of: string;
          cost_per_base_unit: number | null;
          cost_per_portion: number | null;
          created_at: string;
          created_by: string | null;
          currency: string;
          deleted_at: string | null;
          deleted_by: string | null;
          entry_number: number;
          group_id: string;
          id: string;
          method_version: number;
          reason: Database["costing"]["Enums"]["cost_snapshot_reason"];
          recipe_id: string;
          recipe_version_id: string;
          reliability: Database["costing"]["Enums"]["cost_reliability"];
          restaurant_id: string;
          total_cost: number | null;
          total_gross_cost: number | null;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          as_of: string;
          cost_per_base_unit?: number | null;
          cost_per_portion?: number | null;
          created_at?: string;
          created_by?: string | null;
          currency?: string;
          deleted_at?: string | null;
          deleted_by?: string | null;
          entry_number?: never;
          group_id: string;
          id?: string;
          method_version?: number;
          reason: Database["costing"]["Enums"]["cost_snapshot_reason"];
          recipe_id: string;
          recipe_version_id: string;
          reliability: Database["costing"]["Enums"]["cost_reliability"];
          restaurant_id: string;
          total_cost?: number | null;
          total_gross_cost?: number | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          as_of?: string;
          cost_per_base_unit?: number | null;
          cost_per_portion?: number | null;
          created_at?: string;
          created_by?: string | null;
          currency?: string;
          deleted_at?: string | null;
          deleted_by?: string | null;
          entry_number?: never;
          group_id?: string;
          id?: string;
          method_version?: number;
          reason?: Database["costing"]["Enums"]["cost_snapshot_reason"];
          recipe_id?: string;
          recipe_version_id?: string;
          reliability?: Database["costing"]["Enums"]["cost_reliability"];
          restaurant_id?: string;
          total_cost?: number | null;
          total_gross_cost?: number | null;
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
      apply_price: { Args: { p_request_id: string }; Returns: undefined };
      apply_price_direction: { Args: { p_request_id: string }; Returns: undefined };
      archive_scenario: { Args: { p_reason: string; p_scenario_id: string }; Returns: undefined };
      check_reference: {
        Args: {
          p_req: Omit<
            Database["workflow"]["Tables"]["approval_requests"]["Row"],
            Database["workflow"]["Tables"]["approval_requests"]["ComputedFields"]
          >;
        };
        Returns: undefined;
      };
      create_scenario: {
        Args: { p_name: string; p_reason: string; p_restaurant_id: string };
        Returns: string;
      };
      daily_refresh: { Args: { p_day?: string }; Returns: undefined };
      data_quality: {
        Args: { p_restaurant_id: string };
        Returns: {
          done: number;
          hidden: number;
          indicator: string;
          total: number;
        }[];
      };
      data_quality_items: {
        Args: { p_indicator: string; p_limit?: number; p_offset?: number; p_restaurant_id: string };
        Returns: {
          detail: string;
          item: string;
          item_id: string;
          kind: string;
          total_rows: number;
        }[];
      };
      data_quality_places: {
        Args: { p_limit?: number; p_offset?: number };
        Returns: {
          done: number;
          indicator: string;
          restaurant: string;
          restaurant_id: string;
          total: number;
        }[];
      };
      enqueue_price: { Args: { p_price_record_id: string }; Returns: undefined };
      enqueue_recalc: {
        Args: {
          p_price_record_id?: string;
          p_reason: Database["costing"]["Enums"]["cost_snapshot_reason"];
          p_recipe_ids: string[];
          p_restaurant_ids: string[];
          p_source_recipe_id?: string;
        };
        Returns: undefined;
      };
      enqueue_restaurant: {
        Args: {
          p_reason: Database["costing"]["Enums"]["cost_snapshot_reason"];
          p_restaurant_id: string;
        };
        Returns: undefined;
      };
      fit: { Args: { p_limit: number; p_value: number }; Returns: number };
      has_scope_permission: {
        Args: {
          p_brand_id: string;
          p_group_id: string;
          p_permission: string;
          p_restaurant_id: string;
          p_scope: Database["core"]["Enums"]["scope_type"];
        };
        Returns: boolean;
      };
      home_board: {
        Args: { p_restaurant_id: string };
        Returns: {
          amount: number;
          detail: string;
          item: string;
          item_id: string;
          kind: string;
          section: string;
        }[];
      };
      ingredient_line_cost: {
        Args: {
          p_as_of?: string;
          p_basis?: string;
          p_ingredient_id: string;
          p_process_id?: string;
          p_quantity: number;
          p_restaurant_id: string;
          p_unit_id: string;
        };
        Returns: {
          base_quantity: number;
          inherited: boolean;
          line_cost: number;
          price_level: string;
          price_record_id: string;
          purchase_quantity: number;
          status: string;
          unit_cost: number;
        }[];
      };
      insert_approved_price: {
        Args: {
          p_req: Omit<
            Database["workflow"]["Tables"]["approval_requests"]["Row"],
            Database["workflow"]["Tables"]["approval_requests"]["ComputedFields"]
          >;
        };
        Returns: undefined;
      };
      log_report: {
        Args: {
          p_format: string;
          p_from?: string;
          p_recipe_id?: string;
          p_report: string;
          p_restaurant_id: string;
          p_rows?: number;
          p_to?: string;
        };
        Returns: undefined;
      };
      month_end_snapshots: { Args: Record<PropertyKey, never>; Returns: undefined };
      notify_cost_changed: { Args: { p_recipe_id: string }; Returns: undefined };
      package_amounts: {
        Args: {
          p_discount: number;
          p_document: Database["costing"]["Enums"]["price_document"];
          p_includes_vat: boolean;
          p_price: number;
          p_vat_rate: number;
        };
        Returns: {
          gross_amount: number;
          net_amount: number;
        }[];
      };
      price_impact: {
        Args: { p_limit?: number; p_offset?: number; p_price_record_id: string };
        Returns: {
          calculated_at: string;
          cost_after: number;
          cost_before: number;
          difference: number;
          difference_pct: number;
          ingredient: string;
          recipe: string;
          recipe_id: string;
          restaurant: string;
          restaurant_id: string;
          total_rows: number;
          valid_from: string;
          version_changed: boolean;
        }[];
      };
      price_rows: {
        Args: { p_as_of: string; p_ingredient_id: string; p_restaurant_id: string };
        Returns: {
          base_unit: string;
          document_type: string;
          gross_unit_cost: number;
          ingredient_id: string;
          inherited: boolean;
          net_unit_cost: number;
          price_level: string;
          price_record_id: string;
          product_description: string;
          purchase_product_id: string;
          stale: boolean;
          status: string;
          unit_cost: number;
          valid_from: string;
        }[];
      };
      price_view_brand_ids: { Args: Record<PropertyKey, never>; Returns: string[] };
      price_view_group_ids: { Args: Record<PropertyKey, never>; Returns: string[] };
      process_recalc_queue: { Args: { p_limit?: number }; Returns: number };
      propose_price: {
        Args: {
          p_brand_id: string;
          p_discount_amount: number;
          p_document_type: string;
          p_notes: string;
          p_package_price: number;
          p_price_includes_vat: boolean;
          p_purchase_product_id: string;
          p_reason: string;
          p_restaurant_id: string;
          p_scope_type: string;
          p_source: string;
          p_supplier_id: string;
          p_valid_from: string;
          p_vat_rate: number;
        };
        Returns: string;
      };
      purchase_quantity: {
        Args: { p_base: number; p_basis: string; p_cleaning: number; p_cooking: number };
        Returns: number;
      };
      quality_allowed: { Args: { p_restaurant_id: string }; Returns: boolean };
      quality_indicators: { Args: { p_restaurant_id: string }; Returns: string[] };
      quality_items: {
        Args: { p_restaurant_id: string };
        Returns: {
          detail: string;
          indicator: string;
          item: string;
          item_id: string;
          kind: string;
          ok: boolean;
        }[];
      };
      quality_places: {
        Args: Record<PropertyKey, never>;
        Returns: {
          id: string;
          name: string;
        }[];
      };
      recalc_status: {
        Args: Record<PropertyKey, never>;
        Returns: {
          failed: number;
          pending: number;
        }[];
      };
      recipe_cost: {
        Args: { p_restaurant_id: string; p_version_id: string };
        Returns: {
          cost_per_base_unit: number;
          cost_per_portion: number;
          reliability: Database["costing"]["Enums"]["cost_reliability"];
          total_cost: number;
          total_gross_cost: number;
        }[];
      };
      recipe_cost_lines: {
        Args: { p_restaurant_id: string; p_version_id: string };
        Returns: {
          base_quantity: number;
          ingredient_id: string;
          item: string;
          line_cost: number;
          line_gross_cost: number;
          line_order: number;
          quantity: number;
          quantity_basis: string;
          share_pct: number;
          status: string;
          sub_recipe_id: string;
          unit_id: string;
        }[];
      };
      recipe_line_costs_internal: {
        Args: { p_as_of: string; p_memo?: Json; p_restaurant_id: string; p_version_id: string };
        Returns: Database["costing"]["CompositeTypes"]["recipe_cost_line"][];
        SetofOptions: {
          from: "*";
          to: "recipe_cost_line";
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      recipe_totals_internal: {
        Args: { p_as_of: string; p_memo?: Json; p_restaurant_id: string; p_version_id: string };
        Returns: Database["costing"]["CompositeTypes"]["recipe_cost_total"];
        SetofOptions: {
          from: "*";
          to: "recipe_cost_total";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      recipes_above: { Args: { p_recipe_ids: string[] }; Returns: string[] };
      recipes_below: { Args: { p_recipe_id: string }; Returns: string[] };
      recipes_using_ingredient: { Args: { p_ingredient_id: string }; Returns: string[] };
      reference_price: {
        Args: {
          p_as_of: string;
          p_brand_id: string;
          p_group_id: string;
          p_ingredient_id: string;
          p_restaurant_id: string;
          p_scope: Database["core"]["Enums"]["scope_type"];
        };
        Returns: {
          gross_unit_cost: number;
          net_unit_cost: number;
          price_record_id: string;
          valid_from: string;
        }[];
      };
      refresh_recipes: {
        Args: {
          p_reason: Database["costing"]["Enums"]["cost_snapshot_reason"];
          p_recipe_ids: string[];
          p_restaurant_ids: string[];
        };
        Returns: undefined;
      };
      remove_scenario_override: {
        Args: { p_override_id: string; p_reason: string };
        Returns: undefined;
      };
      report_cost_changes: {
        Args: {
          p_from: string;
          p_limit?: number;
          p_offset?: number;
          p_restaurant_id: string;
          p_to: string;
        };
        Returns: {
          changed_on: string;
          current_cost: number;
          difference: number;
          difference_pct: number;
          in_use: boolean;
          previous: number;
          reason: string;
          recipe: string;
          recipe_id: string;
          recipe_type: string;
          total_rows: number;
          version_number: number;
        }[];
      };
      report_exports: {
        Args: { p_limit?: number };
        Returns: {
          format: string;
          occurred_at: string;
          person: string;
          report: string;
          restaurant: string;
          rows_count: number;
        }[];
      };
      report_ingredients: {
        Args: { p_limit?: number; p_offset?: number; p_restaurant_id: string };
        Returns: {
          category: string;
          item_id: string;
          name: string;
          stale: boolean;
          status: string;
          total_rows: number;
          unit: string;
          unit_cost: number;
          valid_from: string;
        }[];
      };
      report_list: { Args: { p_restaurant_id: string }; Returns: string[] };
      report_places: {
        Args: Record<PropertyKey, never>;
        Returns: {
          id: string;
          name: string;
        }[];
      };
      report_quality: {
        Args: { p_limit?: number; p_offset?: number; p_restaurant_id: string };
        Returns: {
          detail: string;
          indicator: string;
          item: string;
          item_id: string;
          kind: string;
          total_rows: number;
        }[];
      };
      report_recipe_ids: { Args: { p_restaurant_id: string }; Returns: string[] };
      report_recipes: {
        Args: { p_limit?: number; p_offset?: number; p_restaurant_id: string; p_search?: string };
        Returns: {
          code: string;
          name: string;
          recipe_id: string;
          recipe_type: string;
          total_rows: number;
        }[];
      };
      report_usage: {
        Args: { p_limit?: number; p_offset?: number; p_restaurant_id: string };
        Returns: {
          component: string;
          item_id: string;
          kind: string;
          quantity: number;
          recipe: string;
          recipe_id: string;
          through: string;
          total_rows: number;
          unit: string;
          version_number: number;
        }[];
      };
      report_yields: {
        Args: { p_limit?: number; p_offset?: number; p_restaurant_id: string };
        Returns: {
          approved_at: string;
          cleaning_yield: number;
          cooking_factor: number;
          cut: string;
          ingredient: string;
          item_id: string;
          process: string;
          supplier: string;
          total_rows: number;
          waste: number;
        }[];
      };
      require_recipe_cost: {
        Args: { p_restaurant_id: string; p_version_id: string };
        Returns: undefined;
      };
      require_report: { Args: { p_report: string; p_restaurant_id: string }; Returns: undefined };
      require_report_recipe: {
        Args: { p_recipe_id: string; p_report: string; p_restaurant_id: string };
        Returns: undefined;
      };
      require_scenario: {
        Args: { p_active?: boolean; p_scenario_id: string };
        Returns: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          name: string;
          restaurant_id: string;
          status: Database["costing"]["Enums"]["scenario_status"];
          updated_at: string;
          updated_by: string | null;
        };
        SetofOptions: {
          from: "*";
          to: "cost_scenarios";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      resolve_price: {
        Args: { p_as_of?: string; p_ingredient_id: string; p_restaurant_id: string };
        Returns: {
          base_unit: string;
          document_type: string;
          gross_unit_cost: number;
          inherited: boolean;
          net_unit_cost: number;
          price_level: string;
          price_record_id: string;
          product_description: string;
          purchase_product_id: string;
          stale: boolean;
          status: string;
          unit_cost: number;
          valid_from: string;
        }[];
      };
      resolve_price_internal: {
        Args: { p_as_of: string; p_ingredient_id: string; p_restaurant_id: string };
        Returns: {
          base_unit: string;
          document_type: string;
          gross_unit_cost: number;
          inherited: boolean;
          net_unit_cost: number;
          price_level: string;
          price_record_id: string;
          product_description: string;
          purchase_product_id: string;
          stale: boolean;
          status: string;
          unit_cost: number;
          valid_from: string;
        }[];
      };
      resolve_prices: {
        Args: { p_as_of?: string; p_restaurant_id: string };
        Returns: {
          base_unit: string;
          document_type: string;
          gross_unit_cost: number;
          ingredient_id: string;
          inherited: boolean;
          net_unit_cost: number;
          price_level: string;
          price_record_id: string;
          product_description: string;
          purchase_product_id: string;
          stale: boolean;
          status: string;
          unit_cost: number;
          valid_from: string;
        }[];
      };
      restaurant_cost_summary: {
        Args: { p_restaurant_id: string };
        Returns: {
          complete: number;
          incomplete: number;
          stale: number;
          total: number;
          updated_at: string;
        }[];
      };
      restaurant_costs: {
        Args: {
          p_limit?: number;
          p_offset?: number;
          p_order?: string;
          p_recipe_id?: string;
          p_reliability?: Database["costing"]["Enums"]["cost_reliability"];
          p_restaurant_id: string;
          p_search?: string;
        };
        Returns: {
          base_unit: string;
          code: string;
          cost_per_base_unit: number;
          cost_per_portion: number;
          name: string;
          portions: number;
          recipe_id: string;
          recipe_type: string;
          recipe_version_id: string;
          reliability: Database["costing"]["Enums"]["cost_reliability"];
          total_cost: number;
          total_gross_cost: number;
          total_rows: number;
          updated_at: string;
        }[];
      };
      restaurant_recipes: { Args: { p_restaurant_id: string }; Returns: string[] };
      scaled_cost: {
        Args: { p_factor: number; p_restaurant_id: string; p_version_id: string };
        Returns: {
          reliability: Database["costing"]["Enums"]["cost_reliability"];
          total_cost: number;
          total_gross_cost: number;
        }[];
      };
      scenario_changes: {
        Args: { p_scenario_id: string };
        Returns: {
          applies: boolean;
          cleaning_yield: number;
          cooking_factor: number;
          id: string;
          item: string;
          kind: string;
          original_quantity: number;
          quantity: number;
          recipe: string;
          supplier: string;
          unit: string;
          unit_cost: number;
        }[];
      };
      scenario_ingredients: {
        Args: { p_scenario_id: string };
        Returns: {
          id: string;
          name: string;
          unit: string;
          unit_cost: number;
        }[];
      };
      scenario_recipe_lines: {
        Args: { p_recipe_id: string; p_scenario_id: string };
        Returns: {
          id: string;
          item: string;
          line_order: number;
          quantity: number;
          unit: string;
        }[];
      };
      scenario_recipes: {
        Args: { p_scenario_id: string };
        Returns: {
          id: string;
          name: string;
        }[];
      };
      scenario_result: {
        Args: { p_limit?: number; p_offset?: number; p_scenario_id: string };
        Returns: {
          changed_rows: number;
          cost_simulated: number;
          cost_today: number;
          difference: number;
          difference_pct: number;
          portion_simulated: number;
          portion_today: number;
          recipe: string;
          recipe_id: string;
          reliability: Database["costing"]["Enums"]["cost_reliability"];
          top_drop: number;
          top_drop_recipe: string;
          top_rise: number;
          top_rise_recipe: string;
          total_rows: number;
        }[];
      };
      search_text: { Args: { p_text: string }; Returns: string };
      set_scenario_override: {
        Args: {
          p_cleaning_yield?: number;
          p_cooking_factor?: number;
          p_ingredient_id?: string;
          p_kind: string;
          p_quantity?: number;
          p_reason: string;
          p_recipe_component_id?: string;
          p_scenario_id: string;
          p_supplier_id?: string;
          p_unit_cost?: number;
        };
        Returns: undefined;
      };
      store_recipe_cost: {
        Args: {
          p_group_id: string;
          p_lines: Database["costing"]["CompositeTypes"]["recipe_cost_line"][];
          p_reason: Database["costing"]["Enums"]["cost_snapshot_reason"];
          p_recipe_id: string;
          p_restaurant_id: string;
          p_total: Database["costing"]["CompositeTypes"]["recipe_cost_total"];
          p_version_id: string;
        };
        Returns: undefined;
      };
      totals_of_lines: {
        Args: {
          p_lines: Database["costing"]["CompositeTypes"]["recipe_cost_line"][];
          p_version_id: string;
        };
        Returns: Database["costing"]["CompositeTypes"]["recipe_cost_total"];
        SetofOptions: {
          from: "*";
          to: "recipe_cost_total";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      update_price_settings: {
        Args: {
          p_approval_variation_pct: number;
          p_group_id: string;
          p_lookback_days?: number;
          p_reason: string;
          p_stale_days: number;
          p_yield_alert_pct?: number;
        };
        Returns: undefined;
      };
      update_yield_alert: {
        Args: { p_group_id: string; p_reason: string; p_yield_alert_pct: number };
        Returns: undefined;
      };
      valid_from_floor: {
        Args: {
          p_brand_id: string;
          p_product_id: string;
          p_restaurant_id: string;
          p_scope: Database["core"]["Enums"]["scope_type"];
        };
        Returns: string;
      };
      visible_recipe_ids: { Args: Record<PropertyKey, never>; Returns: string[] };
    };
    Enums: {
      cost_reliability: "verified" | "estimated" | "stale" | "incomplete";
      cost_snapshot_reason:
        | "publish"
        | "price_change"
        | "yield_change"
        | "assignment"
        | "legal_entity_change"
        | "restaurant_reopened"
        | "daily"
        | "month_end";
      price_document: "invoice" | "no_invoice";
      price_source: "manual" | "test_value" | "excel_import" | "invoice";
      scenario_override_kind: "price" | "yield" | "quantity";
      scenario_status: "active" | "archived";
    };
    CompositeTypes: {
      recipe_cost_line: {
        component_id: string | null;
        line_order: number | null;
        item: string | null;
        ingredient_id: string | null;
        sub_recipe_id: string | null;
        sub_recipe_version_id: string | null;
        quantity: number | null;
        unit_id: string | null;
        quantity_basis: string | null;
        base_quantity: number | null;
        purchase_quantity: number | null;
        yield_profile_id: string | null;
        cleaning_yield: number | null;
        cooking_factor: number | null;
        price_record_id: string | null;
        price_level: string | null;
        package_base_quantity: number | null;
        vat_condition: string | null;
        unit_cost: number | null;
        gross_unit_cost: number | null;
        line_cost: number | null;
        line_gross_cost: number | null;
        estimated: boolean | null;
        stale: boolean | null;
        status: string | null;
      };
      recipe_cost_total: {
        total_cost: number | null;
        total_gross_cost: number | null;
        cost_per_base_unit: number | null;
        cost_per_portion: number | null;
        reliability: Database["costing"]["Enums"]["cost_reliability"] | null;
      };
    };
  };
  imports: {
    Tables: {
      import_errors: {
        Row: {
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          field: string | null;
          group_id: string;
          id: string;
          job_id: string;
          message: string;
          row_id: string | null;
          row_number: number | null;
          severity: Database["imports"]["Enums"]["issue_severity"];
          sheet: string | null;
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
          field?: string | null;
          group_id: string;
          id?: string;
          job_id: string;
          message: string;
          row_id?: string | null;
          row_number?: number | null;
          severity?: Database["imports"]["Enums"]["issue_severity"];
          sheet?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          field?: string | null;
          group_id?: string;
          id?: string;
          job_id?: string;
          message?: string;
          row_id?: string | null;
          row_number?: number | null;
          severity?: Database["imports"]["Enums"]["issue_severity"];
          sheet?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "import_errors_job_fkey";
            columns: ["job_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "import_jobs";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "import_errors_row_fkey";
            columns: ["row_id", "job_id"];
            isOneToOne: false;
            referencedRelation: "import_staging_rows";
            referencedColumns: ["id", "job_id"];
          },
        ];
      };
      import_jobs: {
        Row: {
          brand_id: string;
          code_prefix: string;
          confirmed_at: string | null;
          confirmed_by: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          expected_rows: number | null;
          file_name: string;
          file_sha256: string;
          group_id: string;
          id: string;
          ingredients_confirmed_at: string | null;
          ingredients_confirmed_by: string | null;
          kind: string;
          status: Database["imports"]["Enums"]["job_status"];
          storage_path: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          brand_id: string;
          code_prefix: string;
          confirmed_at?: string | null;
          confirmed_by?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          expected_rows?: number | null;
          file_name: string;
          file_sha256: string;
          group_id: string;
          id?: string;
          ingredients_confirmed_at?: string | null;
          ingredients_confirmed_by?: string | null;
          kind?: string;
          status?: Database["imports"]["Enums"]["job_status"];
          storage_path: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          brand_id?: string;
          code_prefix?: string;
          confirmed_at?: string | null;
          confirmed_by?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          expected_rows?: number | null;
          file_name?: string;
          file_sha256?: string;
          group_id?: string;
          id?: string;
          ingredients_confirmed_at?: string | null;
          ingredients_confirmed_by?: string | null;
          kind?: string;
          status?: Database["imports"]["Enums"]["job_status"];
          storage_path?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [];
      };
      import_prices: {
        Row: {
          created_at: string;
          created_by: string | null;
          currency: string;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          job_id: string;
          price: number | null;
          price_per_kg: number | null;
          row_id: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          currency?: string;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          job_id: string;
          price?: number | null;
          price_per_kg?: number | null;
          row_id: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          currency?: string;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          job_id?: string;
          price?: number | null;
          price_per_kg?: number | null;
          row_id?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "import_prices_job_fkey";
            columns: ["job_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "import_jobs";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "import_prices_row_fkey";
            columns: ["row_id", "job_id"];
            isOneToOne: false;
            referencedRelation: "import_staging_rows";
            referencedColumns: ["id", "job_id"];
          },
        ];
      };
      import_staging_rows: {
        Row: {
          action: Database["imports"]["Enums"]["row_action"] | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          ingredient_id: string | null;
          job_id: string;
          kind: Database["imports"]["Enums"]["row_kind"];
          level: number | null;
          parent_code: string | null;
          parent_row: number | null;
          parsed: NonNullable<Json>;
          raw: NonNullable<Json>;
          recipe_id: string | null;
          recipe_version_id: string | null;
          row_number: number;
          sheet: string;
          source_code: string | null;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          action?: Database["imports"]["Enums"]["row_action"] | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          ingredient_id?: string | null;
          job_id: string;
          kind: Database["imports"]["Enums"]["row_kind"];
          level?: number | null;
          parent_code?: string | null;
          parent_row?: number | null;
          parsed?: NonNullable<Json>;
          raw?: NonNullable<Json>;
          recipe_id?: string | null;
          recipe_version_id?: string | null;
          row_number: number;
          sheet: string;
          source_code?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          action?: Database["imports"]["Enums"]["row_action"] | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          ingredient_id?: string | null;
          job_id?: string;
          kind?: Database["imports"]["Enums"]["row_kind"];
          level?: number | null;
          parent_code?: string | null;
          parent_row?: number | null;
          parsed?: NonNullable<Json>;
          raw?: NonNullable<Json>;
          recipe_id?: string | null;
          recipe_version_id?: string | null;
          row_number?: number;
          sheet?: string;
          source_code?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "import_staging_rows_job_fkey";
            columns: ["job_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "import_jobs";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      brand_recipes: {
        Args: { p_brand_id: string; p_group_id: string };
        Returns: {
          code: string;
          id: string;
          published_unit: string;
        }[];
      };
      cancel_job: { Args: { p_job_id: string; p_reason: string }; Returns: Json };
      category_name: { Args: { p_parsed: Json }; Returns: string };
      changed_since_validation: { Args: { p_what: string }; Returns: undefined };
      clean: { Args: { p_text: string }; Returns: string };
      confirm_ingredients: { Args: { p_job_id: string; p_reason: string }; Returns: Json };
      confirm_recipes: { Args: { p_job_id: string; p_reason: string }; Returns: Json };
      create_job: {
        Args: {
          p_brand_id: string;
          p_code_prefix: string;
          p_expected_rows?: number;
          p_file_name: string;
          p_file_sha256: string;
          p_reason: string;
          p_storage_path: string;
        };
        Returns: Json;
      };
      file_brand_id: { Args: { p_name: string }; Returns: string };
      file_group_id: { Args: { p_name: string }; Returns: string };
      find_job: {
        Args: { p_job_id: string };
        Returns: {
          brand_id: string;
          code_prefix: string;
          confirmed_at: string | null;
          confirmed_by: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          expected_rows: number | null;
          file_name: string;
          file_sha256: string;
          group_id: string;
          id: string;
          ingredients_confirmed_at: string | null;
          ingredients_confirmed_by: string | null;
          kind: string;
          status: Database["imports"]["Enums"]["job_status"];
          storage_path: string;
          updated_at: string;
          updated_by: string | null;
        };
        SetofOptions: {
          from: "*";
          to: "import_jobs";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      full_code: { Args: { p_code: string; p_prefix: string }; Returns: string };
      job_summary: {
        Args: { p_job_id: string };
        Returns: {
          action: Database["imports"]["Enums"]["row_action"];
          kind: Database["imports"]["Enums"]["row_kind"];
          rows: number;
        }[];
      };
      lock_job: {
        Args: { p_job_id: string };
        Returns: {
          brand_id: string;
          code_prefix: string;
          confirmed_at: string | null;
          confirmed_by: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          expected_rows: number | null;
          file_name: string;
          file_sha256: string;
          group_id: string;
          id: string;
          ingredients_confirmed_at: string | null;
          ingredients_confirmed_by: string | null;
          kind: string;
          status: Database["imports"]["Enums"]["job_status"];
          storage_path: string;
          updated_at: string;
          updated_by: string | null;
        };
        SetofOptions: {
          from: "*";
          to: "import_jobs";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      norm: { Args: { p_text: string }; Returns: string };
      num: { Args: { p_value: string }; Returns: number };
      stage_rows: { Args: { p_job_id: string; p_rows: Json }; Returns: Json };
      validate_job: { Args: { p_job_id: string }; Returns: Json };
      visible_job_ids: { Args: Record<PropertyKey, never>; Returns: string[] };
    };
    Enums: {
      issue_severity: "error" | "warning";
      job_status:
        "uploaded" | "staged" | "validated" | "ingredients_confirmed" | "confirmed" | "cancelled";
      row_action: "create" | "reuse" | "skip" | "error";
      row_kind: "ingredient" | "preparation" | "dish" | "line";
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
          code: string;
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
          code: string;
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
          code?: string;
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
          legal_name: string | null;
          name: string;
          status: Database["org"]["Enums"]["unit_status"];
          tax_id: string | null;
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
          legal_name?: string | null;
          name: string;
          status?: Database["org"]["Enums"]["unit_status"];
          tax_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          id?: string;
          legal_name?: string | null;
          name?: string;
          status?: Database["org"]["Enums"]["unit_status"];
          tax_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [];
      };
      legal_entities: {
        Row: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          name: string;
          tax_id: string;
          updated_at: string;
          updated_by: string | null;
          vat_condition: Database["org"]["Enums"]["vat_condition"];
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
          tax_id: string;
          updated_at?: string;
          updated_by?: string | null;
          vat_condition: Database["org"]["Enums"]["vat_condition"];
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          name?: string;
          tax_id?: string;
          updated_at?: string;
          updated_by?: string | null;
          vat_condition?: Database["org"]["Enums"]["vat_condition"];
        };
        Relationships: [
          {
            foreignKeyName: "legal_entities_group_id_fkey";
            columns: ["group_id"];
            isOneToOne: false;
            referencedRelation: "groups";
            referencedColumns: ["id"];
          },
        ];
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
          legal_entity_id: string | null;
          legal_name: string | null;
          locality: string | null;
          name: string;
          opened_on: string | null;
          phone: string | null;
          predecessor_id: string | null;
          site_type: Database["org"]["Enums"]["site_type"];
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
          legal_entity_id?: string | null;
          legal_name?: string | null;
          locality?: string | null;
          name: string;
          opened_on?: string | null;
          phone?: string | null;
          predecessor_id?: string | null;
          site_type?: Database["org"]["Enums"]["site_type"];
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
          legal_entity_id?: string | null;
          legal_name?: string | null;
          locality?: string | null;
          name?: string;
          opened_on?: string | null;
          phone?: string | null;
          predecessor_id?: string | null;
          site_type?: Database["org"]["Enums"]["site_type"];
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
            foreignKeyName: "restaurants_legal_entity_fkey";
            columns: ["legal_entity_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "legal_entities";
            referencedColumns: ["id", "group_id"];
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
        Args: { p_code: string; p_group_id: string; p_name: string; p_reason: string };
        Returns: string;
      };
      create_legal_entity: {
        Args: {
          p_group_id: string;
          p_name: string;
          p_reason: string;
          p_tax_id: string;
          p_vat_condition: string;
        };
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
      set_restaurant_legal_entity: {
        Args: { p_legal_entity_id: string; p_reason: string; p_restaurant_id: string };
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
      update_legal_entity: {
        Args: { p_changes: Json; p_id: string; p_reason: string };
        Returns: undefined;
      };
      update_restaurant: {
        Args: { p_changes: Json; p_id: string; p_reason: string };
        Returns: undefined;
      };
    };
    Enums: {
      site_type: "restaurant" | "central_kitchen" | "production_unit";
      unit_status: "active" | "inactive";
      vat_condition: "registered" | "monotax" | "exempt";
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
  recipes: {
    Tables: {
      component_base_quantities: {
        Row: {
          base_quantity: number;
          base_unit_id: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          recipe_component_id: string;
          recipe_version_id: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          base_quantity: number;
          base_unit_id: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          recipe_component_id: string;
          recipe_version_id: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          base_quantity?: number;
          base_unit_id?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          recipe_component_id?: string;
          recipe_version_id?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "component_base_quantities_recipe_component_id_fkey";
            columns: ["recipe_component_id"];
            isOneToOne: false;
            referencedRelation: "recipe_components";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "component_base_quantities_recipe_version_id_fkey";
            columns: ["recipe_version_id"];
            isOneToOne: false;
            referencedRelation: "recipe_versions";
            referencedColumns: ["id"];
          },
        ];
      };
      recipe_assignments: {
        Row: {
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          recipe_id: string;
          restaurant_id: string;
          updated_at: string;
          updated_by: string | null;
          valid_from: string;
          valid_to: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          recipe_id: string;
          restaurant_id: string;
          updated_at?: string;
          updated_by?: string | null;
          valid_from: string;
          valid_to?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          recipe_id?: string;
          restaurant_id?: string;
          updated_at?: string;
          updated_by?: string | null;
          valid_from?: string;
          valid_to?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "recipe_assignments_recipe_fkey";
            columns: ["recipe_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "recipes";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      recipe_categories: {
        Row: {
          code: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          is_active: boolean;
          kind: Database["recipes"]["Enums"]["category_class"] | null;
          name: string;
          parent_id: string | null;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          code?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          is_active?: boolean;
          kind?: Database["recipes"]["Enums"]["category_class"] | null;
          name: string;
          parent_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          code?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          is_active?: boolean;
          kind?: Database["recipes"]["Enums"]["category_class"] | null;
          name?: string;
          parent_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "recipe_categories_parent_fkey";
            columns: ["parent_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "recipe_categories";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      recipe_components: {
        Row: {
          brand_id: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          ingredient_id: string | null;
          line_order: number;
          no_scale: boolean;
          notes: string | null;
          quantity: number;
          quantity_basis: Database["recipes"]["Enums"]["quantity_basis"];
          recipe_version_id: string;
          restaurant_id: string | null;
          sub_recipe_id: string | null;
          unit_id: string;
          updated_at: string;
          updated_by: string | null;
          yield_profile_id: string | null;
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
          ingredient_id?: string | null;
          line_order: number;
          no_scale?: boolean;
          notes?: string | null;
          quantity: number;
          quantity_basis?: Database["recipes"]["Enums"]["quantity_basis"];
          recipe_version_id: string;
          restaurant_id?: string | null;
          sub_recipe_id?: string | null;
          unit_id: string;
          updated_at?: string;
          updated_by?: string | null;
          yield_profile_id?: string | null;
        };
        Update: {
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          ingredient_id?: string | null;
          line_order?: number;
          no_scale?: boolean;
          notes?: string | null;
          quantity?: number;
          quantity_basis?: Database["recipes"]["Enums"]["quantity_basis"];
          recipe_version_id?: string;
          restaurant_id?: string | null;
          sub_recipe_id?: string | null;
          unit_id?: string;
          updated_at?: string;
          updated_by?: string | null;
          yield_profile_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "recipe_components_sub_recipe_fkey";
            columns: ["sub_recipe_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "recipes";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "recipe_components_version_fkey";
            columns: ["recipe_version_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "recipe_versions";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      recipe_media: {
        Row: {
          brand_id: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          description: string | null;
          group_id: string;
          id: string;
          kind: Database["recipes"]["Enums"]["media_kind"];
          recipe_id: string;
          recipe_version_id: string;
          restaurant_id: string | null;
          storage_path: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          group_id: string;
          id?: string;
          kind: Database["recipes"]["Enums"]["media_kind"];
          recipe_id: string;
          recipe_version_id: string;
          restaurant_id?: string | null;
          storage_path: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          group_id?: string;
          id?: string;
          kind?: Database["recipes"]["Enums"]["media_kind"];
          recipe_id?: string;
          recipe_version_id?: string;
          restaurant_id?: string | null;
          storage_path?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "recipe_media_recipe_fkey";
            columns: ["recipe_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "recipes";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "recipe_media_version_fkey";
            columns: ["recipe_version_id", "recipe_id"];
            isOneToOne: false;
            referencedRelation: "recipe_versions";
            referencedColumns: ["id", "recipe_id"];
          },
        ];
      };
      recipe_step_dependencies: {
        Row: {
          brand_id: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          depends_on_step_id: string;
          group_id: string;
          id: string;
          restaurant_id: string | null;
          step_id: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          depends_on_step_id: string;
          group_id: string;
          id?: string;
          restaurant_id?: string | null;
          step_id: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          brand_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          depends_on_step_id?: string;
          group_id?: string;
          id?: string;
          restaurant_id?: string | null;
          step_id?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "recipe_step_dependencies_depends_fkey";
            columns: ["depends_on_step_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "recipe_steps";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "recipe_step_dependencies_step_fkey";
            columns: ["step_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "recipe_steps";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      recipe_steps: {
        Row: {
          active_minutes: number;
          brand_id: string | null;
          control_point: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          equipment: string | null;
          equipment_capacity: number | null;
          equipment_capacity_unit_id: string | null;
          group_id: string;
          id: string;
          instructions: string;
          kind: Database["recipes"]["Enums"]["step_kind"];
          passive_minutes: number;
          recipe_version_id: string;
          restaurant_id: string | null;
          sector: string | null;
          step_number: number;
          updated_at: string;
          updated_by: string | null;
          workers: number | null;
        };
        ComputedFields: never;
        Insert: {
          active_minutes?: number;
          brand_id?: string | null;
          control_point?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          equipment?: string | null;
          equipment_capacity?: number | null;
          equipment_capacity_unit_id?: string | null;
          group_id: string;
          id?: string;
          instructions: string;
          kind?: Database["recipes"]["Enums"]["step_kind"];
          passive_minutes?: number;
          recipe_version_id: string;
          restaurant_id?: string | null;
          sector?: string | null;
          step_number: number;
          updated_at?: string;
          updated_by?: string | null;
          workers?: number | null;
        };
        Update: {
          active_minutes?: number;
          brand_id?: string | null;
          control_point?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          equipment?: string | null;
          equipment_capacity?: number | null;
          equipment_capacity_unit_id?: string | null;
          group_id?: string;
          id?: string;
          instructions?: string;
          kind?: Database["recipes"]["Enums"]["step_kind"];
          passive_minutes?: number;
          recipe_version_id?: string;
          restaurant_id?: string | null;
          sector?: string | null;
          step_number?: number;
          updated_at?: string;
          updated_by?: string | null;
          workers?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "recipe_steps_version_fkey";
            columns: ["recipe_version_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "recipe_versions";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      recipe_versions: {
        Row: {
          approval_request_id: string | null;
          approved_by: string | null;
          brand_id: string | null;
          change_summary: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          description: string | null;
          group_id: string;
          id: string;
          portion_grams: number | null;
          portions: number | null;
          presentation_notes: string | null;
          previous_version_id: string | null;
          published_at: string | null;
          recipe_id: string;
          restaurant_id: string | null;
          review_requested_by: string | null;
          status: Database["core"]["Enums"]["version_status"];
          storage_notes: string | null;
          updated_at: string;
          updated_by: string | null;
          version_number: number;
          yield_quantity: number | null;
          yield_unit_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          approval_request_id?: string | null;
          approved_by?: string | null;
          brand_id?: string | null;
          change_summary?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          group_id: string;
          id?: string;
          portion_grams?: number | null;
          portions?: number | null;
          presentation_notes?: string | null;
          previous_version_id?: string | null;
          published_at?: string | null;
          recipe_id: string;
          restaurant_id?: string | null;
          review_requested_by?: string | null;
          status?: Database["core"]["Enums"]["version_status"];
          storage_notes?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          version_number: number;
          yield_quantity?: number | null;
          yield_unit_id?: string | null;
        };
        Update: {
          approval_request_id?: string | null;
          approved_by?: string | null;
          brand_id?: string | null;
          change_summary?: string | null;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          group_id?: string;
          id?: string;
          portion_grams?: number | null;
          portions?: number | null;
          presentation_notes?: string | null;
          previous_version_id?: string | null;
          published_at?: string | null;
          recipe_id?: string;
          restaurant_id?: string | null;
          review_requested_by?: string | null;
          status?: Database["core"]["Enums"]["version_status"];
          storage_notes?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          version_number?: number;
          yield_quantity?: number | null;
          yield_unit_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "recipe_versions_previous_fkey";
            columns: ["previous_version_id", "recipe_id"];
            isOneToOne: false;
            referencedRelation: "recipe_versions";
            referencedColumns: ["id", "recipe_id"];
          },
          {
            foreignKeyName: "recipe_versions_recipe_fkey";
            columns: ["recipe_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "recipes";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
      recipes: {
        Row: {
          brand_id: string | null;
          category_id: string | null;
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          group_id: string;
          id: string;
          is_active: boolean;
          name: string;
          recipe_type: Database["recipes"]["Enums"]["recipe_type"];
          restaurant_id: string | null;
          scope_type: Database["recipes"]["Enums"]["recipe_scope"];
          sector: string | null;
          short_name: string | null;
          station: string | null;
          technical_owner_id: string | null;
          updated_at: string;
          updated_by: string | null;
          variant_of_recipe_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          brand_id?: string | null;
          category_id?: string | null;
          code: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id: string;
          id?: string;
          is_active?: boolean;
          name: string;
          recipe_type: Database["recipes"]["Enums"]["recipe_type"];
          restaurant_id?: string | null;
          scope_type: Database["recipes"]["Enums"]["recipe_scope"];
          sector?: string | null;
          short_name?: string | null;
          station?: string | null;
          technical_owner_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          variant_of_recipe_id?: string | null;
        };
        Update: {
          brand_id?: string | null;
          category_id?: string | null;
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          group_id?: string;
          id?: string;
          is_active?: boolean;
          name?: string;
          recipe_type?: Database["recipes"]["Enums"]["recipe_type"];
          restaurant_id?: string | null;
          scope_type?: Database["recipes"]["Enums"]["recipe_scope"];
          sector?: string | null;
          short_name?: string | null;
          station?: string | null;
          technical_owner_id?: string | null;
          updated_at?: string;
          updated_by?: string | null;
          variant_of_recipe_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "recipes_category_fkey";
            columns: ["category_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "recipe_categories";
            referencedColumns: ["id", "group_id"];
          },
          {
            foreignKeyName: "recipes_variant_fkey";
            columns: ["variant_of_recipe_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "recipes";
            referencedColumns: ["id", "group_id"];
          },
        ];
      };
    };
    Views: {
      top_categories: {
        Row: {
          category_class: Database["recipes"]["Enums"]["category_class"] | null;
          code: string | null;
          created_at: string | null;
          group_id: string | null;
          id: string | null;
          is_active: boolean | null;
          name: string | null;
          updated_at: string | null;
        };
        ComputedFields: never;
        Relationships: [];
      };
    };
    Functions: {
      add_media: {
        Args: {
          p_description: string;
          p_kind: Database["recipes"]["Enums"]["media_kind"];
          p_reason: string;
          p_recipe_id: string;
          p_storage_path: string;
        };
        Returns: Json;
      };
      allowed: {
        Args: {
          p_brand_id: string;
          p_group_id: string;
          p_permission: string;
          p_restaurant_id: string;
        };
        Returns: boolean;
      };
      apply_publish_version: { Args: { p_request_id: string }; Returns: undefined };
      archive_category: { Args: { p_id: string; p_reason: string }; Returns: undefined };
      archive_recipe: { Args: { p_reason: string; p_recipe_id: string }; Returns: Json };
      can_manage_category: {
        Args: { p_class: Database["recipes"]["Enums"]["category_class"]; p_group_id: string };
        Returns: boolean;
      };
      can_see_version: { Args: { p_version_id: string }; Returns: boolean };
      can_upload_media: { Args: { p_name: string }; Returns: boolean };
      can_view_recipe: { Args: { p_recipe_id: string }; Returns: boolean };
      can_work_recipe: { Args: { p_recipe_id: string }; Returns: boolean };
      category_overview: {
        Args: { p_group_id: string };
        Returns: {
          category_class: Database["recipes"]["Enums"]["category_class"];
          code: string;
          id: string;
          is_active: boolean;
          mismatched: number;
          name: string;
          uses: number;
        }[];
      };
      category_usage: {
        Args: Record<PropertyKey, never>;
        Returns: {
          category_id: string;
          recipes: number;
        }[];
      };
      compare_versions: {
        Args: { p_new: string; p_old: string };
        Returns: {
          basis: Database["recipes"]["Enums"]["quantity_basis"];
          change: string;
          ingredient: string;
          new_quantity: number;
          old_quantity: number;
          unit: string;
        }[];
      };
      cooking_loss: {
        Args: { p_version_id: string };
        Returns: {
          factor: number;
          input_grams: number;
          output_grams: number;
          status: string;
        }[];
      };
      copy_version_content: { Args: { p_from: string; p_to: string }; Returns: undefined };
      create_category: {
        Args: { p_group_id: string; p_name: string; p_parent_id?: string; p_reason: string };
        Returns: string;
      };
      create_recipe: {
        Args: {
          p_brand_id: string;
          p_category_id: string;
          p_code: string;
          p_group_id: string;
          p_name: string;
          p_reason: string;
          p_restaurant_id: string;
          p_type: Database["recipes"]["Enums"]["recipe_type"];
        };
        Returns: Json;
      };
      create_top_category: {
        Args: {
          p_class: Database["recipes"]["Enums"]["category_class"];
          p_group_id: string;
          p_name: string;
          p_reason: string;
        };
        Returns: string;
      };
      create_variant: {
        Args: {
          p_code: string;
          p_master_id: string;
          p_name: string;
          p_reason: string;
          p_restaurant_id: string;
        };
        Returns: Json;
      };
      critical_path: {
        Args: { p_version_id: string };
        Returns: {
          active_minutes: number;
          total_minutes: number;
        }[];
      };
      deactivate_top_category: {
        Args: {
          p_class: Database["recipes"]["Enums"]["category_class"];
          p_id: string;
          p_reason: string;
          p_target_id?: string;
        };
        Returns: number;
      };
      default_categories: {
        Args: Record<PropertyKey, never>;
        Returns: {
          category_class: Database["recipes"]["Enums"]["category_class"];
          code: string;
          name: string;
        }[];
      };
      first_invalid_line: {
        Args: { p_version_id: string };
        Returns: {
          item: string;
          line_order: number;
          why: string;
        }[];
      };
      freeze_base_quantities: { Args: { p_version_id: string }; Returns: undefined };
      install_default_categories: { Args: { p_group_id: string }; Returns: number };
      kitchen_card: { Args: { p_recipe_id: string }; Returns: Json };
      lock_sub_graph: { Args: { p_group_id: string }; Returns: undefined };
      map_legacy_categories: {
        Args: { p_equivalences?: Json; p_group_id: string };
        Returns: number;
      };
      media_recipe_id: { Args: { p_name: string }; Returns: string };
      new_version: { Args: { p_reason: string; p_recipe_id: string }; Returns: Json };
      notify_recipe_changed: {
        Args: { p_approver: string; p_version_id: string };
        Returns: undefined;
      };
      open_draft: {
        Args: { p_expected_updated_at: string; p_version_id: string };
        Returns: {
          approval_request_id: string | null;
          approved_by: string | null;
          brand_id: string | null;
          change_summary: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          description: string | null;
          group_id: string;
          id: string;
          portion_grams: number | null;
          portions: number | null;
          presentation_notes: string | null;
          previous_version_id: string | null;
          published_at: string | null;
          recipe_id: string;
          restaurant_id: string | null;
          review_requested_by: string | null;
          status: Database["core"]["Enums"]["version_status"];
          storage_notes: string | null;
          updated_at: string;
          updated_by: string | null;
          version_number: number;
          yield_quantity: number | null;
          yield_unit_id: string | null;
        };
        SetofOptions: {
          from: "*";
          to: "recipe_versions";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      raise_category_error: {
        Args: {
          p_class: Database["recipes"]["Enums"]["category_class"];
          p_constraint: string;
          p_message: string;
          p_state: string;
        };
        Returns: undefined;
      };
      raise_friendly: {
        Args: { p_constraint: string; p_message: string; p_state: string };
        Returns: undefined;
      };
      reaches: {
        Args: { p_from: string; p_only_published: boolean; p_target: string };
        Returns: boolean;
      };
      reactivate_top_category: {
        Args: {
          p_class: Database["recipes"]["Enums"]["category_class"];
          p_id: string;
          p_reason: string;
        };
        Returns: undefined;
      };
      recipe_usage: {
        Args: { p_recipe_id: string };
        Returns: {
          code: string;
          name: string;
          recipe_id: string;
          status: Database["core"]["Enums"]["version_status"];
          version_number: number;
        }[];
      };
      remove_media: { Args: { p_media_id: string; p_reason: string }; Returns: Json };
      rename_category: {
        Args: { p_id: string; p_name: string; p_reason: string };
        Returns: undefined;
      };
      rename_top_category: {
        Args: {
          p_class: Database["recipes"]["Enums"]["category_class"];
          p_id: string;
          p_name: string;
          p_reason: string;
        };
        Returns: undefined;
      };
      reopen_returned: { Args: { p_version_id: string }; Returns: undefined };
      request_review: { Args: { p_reason: string; p_version_id: string }; Returns: Json };
      save_draft: {
        Args: {
          p_data: Json;
          p_expected_updated_at?: string;
          p_reason: string;
          p_version_id: string;
        };
        Returns: Json;
      };
      scale_version: {
        Args: { p_mode: string; p_target: number; p_unit?: string; p_version_id: string };
        Returns: Json;
      };
      search_subrecipes: {
        Args: { p_limit?: number; p_query: string; p_recipe_id: string };
        Returns: {
          code: string;
          id: string;
          name: string;
          unit: string;
        }[];
      };
      set_assignment: {
        Args: {
          p_assigned: boolean;
          p_reason: string;
          p_recipe_id: string;
          p_restaurant_id: string;
        };
        Returns: Json;
      };
      set_components: {
        Args: {
          p_expected_updated_at?: string;
          p_lines: Json;
          p_reason: string;
          p_version_id: string;
        };
        Returns: Json;
      };
      set_steps: {
        Args: {
          p_expected_updated_at?: string;
          p_reason: string;
          p_steps: Json;
          p_version_id: string;
        };
        Returns: Json;
      };
      sub_depth: { Args: { p_recipe_id: string }; Returns: number };
      sub_height: { Args: { p_recipe_id: string }; Returns: number };
      sub_in_scope: { Args: { p_parent: string; p_sub: string }; Returns: boolean };
      today: { Args: Record<PropertyKey, never>; Returns: string };
      top_category_group: {
        Args: { p_class: Database["recipes"]["Enums"]["category_class"]; p_id: string };
        Returns: string;
      };
      unit_to_base: { Args: { p_unit_id: string }; Returns: number };
      update_recipe: { Args: { p_changes: Json; p_id: string; p_reason: string }; Returns: Json };
      variant_diff: {
        Args: { p_variant_id: string };
        Returns: {
          basis: Database["recipes"]["Enums"]["quantity_basis"];
          change: string;
          ingredient: string;
          new_quantity: number;
          old_quantity: number;
          unit: string;
        }[];
      };
      version_allergens: {
        Args: { p_version_id: string };
        Returns: {
          allergen_id: string;
          code: string;
          name: string;
          status: string;
        }[];
      };
      version_diff: {
        Args: { p_version_id: string };
        Returns: {
          basis: Database["recipes"]["Enums"]["quantity_basis"];
          change: string;
          ingredient: string;
          new_quantity: number;
          old_quantity: number;
          unit: string;
        }[];
      };
      viewable_recipe_ids: { Args: Record<PropertyKey, never>; Returns: string[] };
      visible_media_paths: { Args: Record<PropertyKey, never>; Returns: string[] };
      visible_version_ids: { Args: Record<PropertyKey, never>; Returns: string[] };
      withdraw_review: { Args: { p_reason: string; p_version_id: string }; Returns: Json };
      workable_recipe_ids: { Args: Record<PropertyKey, never>; Returns: string[] };
    };
    Enums: {
      category_class: "purchase" | "subrecipe" | "menu";
      media_kind:
        | "final_product"
        | "plating"
        | "raw_material"
        | "step"
        | "critical_point"
        | "correct_example"
        | "incorrect_example";
      quantity_basis: "purchase" | "clean" | "cooked" | "finished";
      recipe_scope: "group" | "brand" | "restaurant";
      recipe_type: "preparation" | "dish" | "unit_component";
      step_kind:
        | "preparation"
        | "cooking"
        | "resting"
        | "fermentation"
        | "cooling"
        | "regeneration"
        | "plating"
        | "other";
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
          entity_id: string | null;
          entity_table: string | null;
          group_id: string;
          id: string;
          previous_values: Json | null;
          proposed_changes: NonNullable<Json>;
          reason: string;
          requested_at: string;
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
          entity_id?: string | null;
          entity_table?: string | null;
          group_id: string;
          id?: string;
          previous_values?: Json | null;
          proposed_changes: NonNullable<Json>;
          reason: string;
          requested_at?: string;
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
          entity_id?: string | null;
          entity_table?: string | null;
          group_id?: string;
          id?: string;
          previous_values?: Json | null;
          proposed_changes?: NonNullable<Json>;
          reason?: string;
          requested_at?: string;
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
          allow_self_approval: boolean;
          apply_function: unknown;
          approver_role_codes: string[] | null;
          code: string;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          description: string | null;
          entity_table: string | null;
          id: string;
          is_active: boolean;
          min_approvers: number;
          name: string;
          required_permission: string;
          updated_at: string;
          updated_by: string | null;
        };
        ComputedFields: never;
        Insert: {
          allow_self_approval?: boolean;
          apply_function: unknown;
          approver_role_codes?: string[] | null;
          code: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          entity_table?: string | null;
          id?: string;
          is_active?: boolean;
          min_approvers?: number;
          name: string;
          required_permission?: string;
          updated_at?: string;
          updated_by?: string | null;
        };
        Update: {
          allow_self_approval?: boolean;
          apply_function?: unknown;
          approver_role_codes?: string[] | null;
          code?: string;
          created_at?: string;
          created_by?: string | null;
          deleted_at?: string | null;
          deleted_by?: string | null;
          description?: string | null;
          entity_table?: string | null;
          id?: string;
          is_active?: boolean;
          min_approvers?: number;
          name?: string;
          required_permission?: string;
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
      approved_request: {
        Args: { p_request_id: string };
        Returns: {
          brand_id: string | null;
          created_at: string;
          created_by: string | null;
          deleted_at: string | null;
          deleted_by: string | null;
          entity_id: string | null;
          entity_table: string | null;
          group_id: string;
          id: string;
          previous_values: Json | null;
          proposed_changes: NonNullable<Json>;
          reason: string;
          requested_at: string;
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
        SetofOptions: {
          from: "*";
          to: "approval_requests";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      can_see_amounts: {
        Args: {
          p_brand_id: string;
          p_group_id: string;
          p_restaurant_id: string;
          p_workflow_code: string;
        };
        Returns: boolean;
      };
      cancel_request: { Args: { p_reason: string; p_request_id: string }; Returns: Json };
      cannot_apply: { Args: { p_why: string }; Returns: undefined };
      decide_approval: {
        Args: { p_comment?: string; p_decision: string; p_request_id: string };
        Returns: Json;
      };
      decision_blocker: { Args: { p_request_id: string }; Returns: string };
      inbox: {
        Args: {
          p_before_created_at?: string;
          p_before_id?: string;
          p_limit?: number;
          p_pending?: boolean;
        };
        Returns: {
          can_decide: boolean;
          entity_table: string;
          id: string;
          place_name: string;
          previous_values: Json;
          proposed_changes: Json;
          reason: string;
          requested_at: string;
          requested_by_name: string;
          resolution_comment: string;
          resolved_at: string;
          resolved_by_name: string;
          status: Database["workflow"]["Enums"]["request_status"];
          summary: string;
          workflow_code: string;
          workflow_name: string;
        }[];
      };
      request_approval: {
        Args: {
          p_brand_id: string;
          p_entity_id: string;
          p_group_id: string;
          p_previous_values: Json;
          p_proposed_changes: Json;
          p_reason: string;
          p_restaurant_id: string;
          p_subject_user_id: string;
          p_workflow_code: string;
        };
        Returns: string;
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
      action: [
        "insert",
        "update",
        "soft_delete",
        "restore",
        "delete",
        "approve",
        "reject",
        "publish",
      ],
      change_origin: [
        "manual",
        "edge_function",
        "agent",
        "import",
        "integration",
        "seed",
        "maintenance",
        "auth",
      ],
      security_event_type: [
        "login_succeeded",
        "login_failed",
        "account_locked",
        "account_unlocked",
        "operation_denied",
        "account_disabled",
        "account_reactivated",
        "account_suspended",
        "account_unsuspended",
        "password_changed",
        "mfa_enrolled",
        "audit_exported",
        "report_exported",
      ],
    },
  },
  catalog: {
    Enums: {
      allergen_status: ["contains", "may_contain", "free_verified"],
      conversion_kind: ["density", "unit_weight"],
      data_source: [
        "manual",
        "excel_import",
        "measured",
        "supplier",
        "calculated",
        "estimated",
        "verified",
      ],
      dimension: ["mass", "volume", "count", "package"],
      yield_status: ["draft", "approved", "superseded"],
    },
  },
  core: {
    Enums: {
      account_status: ["active", "suspended", "deactivated"],
      actor_type: ["user", "service_account"],
      notification_kind: [
        "approval_requested",
        "recipe_changed",
        "recipe_cost_changed",
        "yield_deviation",
      ],
      scope_type: ["group", "brand", "restaurant"],
      version_status: ["draft", "in_review", "approved", "published", "archived"],
    },
  },
  costing: {
    Enums: {
      cost_reliability: ["verified", "estimated", "stale", "incomplete"],
      cost_snapshot_reason: [
        "publish",
        "price_change",
        "yield_change",
        "assignment",
        "legal_entity_change",
        "restaurant_reopened",
        "daily",
        "month_end",
      ],
      price_document: ["invoice", "no_invoice"],
      price_source: ["manual", "test_value", "excel_import", "invoice"],
      scenario_override_kind: ["price", "yield", "quantity"],
      scenario_status: ["active", "archived"],
    },
  },
  imports: {
    Enums: {
      issue_severity: ["error", "warning"],
      job_status: [
        "uploaded",
        "staged",
        "validated",
        "ingredients_confirmed",
        "confirmed",
        "cancelled",
      ],
      row_action: ["create", "reuse", "skip", "error"],
      row_kind: ["ingredient", "preparation", "dish", "line"],
    },
  },
  org: {
    Enums: {
      site_type: ["restaurant", "central_kitchen", "production_unit"],
      unit_status: ["active", "inactive"],
      vat_condition: ["registered", "monotax", "exempt"],
    },
  },
  public: {
    Enums: {},
  },
  recipes: {
    Enums: {
      category_class: ["purchase", "subrecipe", "menu"],
      media_kind: [
        "final_product",
        "plating",
        "raw_material",
        "step",
        "critical_point",
        "correct_example",
        "incorrect_example",
      ],
      quantity_basis: ["purchase", "clean", "cooked", "finished"],
      recipe_scope: ["group", "brand", "restaurant"],
      recipe_type: ["preparation", "dish", "unit_component"],
      step_kind: [
        "preparation",
        "cooking",
        "resting",
        "fermentation",
        "cooling",
        "regeneration",
        "plating",
        "other",
      ],
    },
  },
  workflow: {
    Enums: {
      decision: ["approved", "rejected"],
      request_status: ["pending", "approved", "rejected", "cancelled"],
    },
  },
} as const;
