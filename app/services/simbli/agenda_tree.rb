module Simbli
  # Parses Simbli's GetItemsTreeDTO response (a nested agenda tree) into a flat,
  # depth-first ordered list of agenda items. Identity is the numeric AgendaID;
  # the node's encrypted "ID" is session-scoped and intentionally ignored.
  class AgendaTree
    Item = Data.define(:agenda_id, :title, :has_attachment, :parent_id, :level, :position)

    def self.parse(payload)
      nodes = payload.is_a?(Hash) ? payload["Items"] : payload
      items = []
      position = 0

      walk = lambda do |list|
        Array(list).each do |node|
          position += 1
          items << Item.new(
            agenda_id: node["AgendaID"],
            title: node["Title"].to_s.strip,
            has_attachment: node["HasAttachment"] == true,
            parent_id: node["ParentID"],
            level: node["Level"],
            position: position
          )
          walk.call(node["Children"])
        end
      end

      walk.call(nodes)
      items
    end
  end
end
