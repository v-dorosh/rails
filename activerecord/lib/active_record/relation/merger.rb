require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/keys'

module ActiveRecord
  class Relation
    class Merger
      attr_reader :relation, :other

      def initialize(relation, other)
        @relation = relation

        if other.default_scoped? && other.klass != relation.klass
          @other = other.with_default_scope
        else
          @other = other
        end
      end

      def merge
        HashMerger.new(relation, other.values).merge
      end
    end

    class HashMerger
      attr_reader :relation, :values

      def initialize(relation, values)
        values.assert_valid_keys(*Relation::VALUE_METHODS)

        @relation = relation
        @values   = values
      end

      def normal_values
        Relation::SINGLE_VALUE_METHODS +
          Relation::MULTI_VALUE_METHODS -
          [:where, :order, :bind, :reverse_order, :lock, :create_with, :reordering]
      end

      def merge
        normal_values.each do |name|
          value = values[name]
          relation.send("#{name}!", value) unless value.blank?
        end

        merge_multi_values
        merge_single_values

        relation
      end

      private

      def merge_multi_values
        relation.where_values = merged_wheres
        relation.bind_values  = merged_binds

        if values[:reordering]
          # override any order specified in the original relation
          relation.reorder! values[:order]
        elsif values[:order]
          # merge in order_values from r
          relation.order! values[:order]
        end

        relation.extend(*values[:extending]) unless values[:extending].blank?
      end

      def merge_single_values
        relation.lock_value          = values[:lock] unless relation.lock_value
        relation.reverse_order_value = values[:reverse_order]

        unless values[:create_with].blank?
          relation.create_with_value = (relation.create_with_value || {}).merge(values[:create_with])
        end
      end

      def merged_binds
        if values[:bind]
          (relation.bind_values + values[:bind]).uniq(&:first)
        else
          relation.bind_values
        end
      end

      def merged_wheres
        if values[:where]
          merged_wheres = relation.where_values + values[:where]

          unless relation.where_values.empty?
            # Remove duplicates, last one wins.
            seen = Hash.new { |h,table| h[table] = {} }
            merged_wheres = merged_wheres.reverse.reject { |w|
              nuke = false
              if w.respond_to?(:operator) && w.operator == :==
                name              = w.left.name
                table             = w.left.relation.name
                nuke              = seen[table][name]
                seen[table][name] = true
              end
              nuke
            }.reverse
          end

          merged_wheres
        else
          relation.where_values
        end
      end
    end
  end
end