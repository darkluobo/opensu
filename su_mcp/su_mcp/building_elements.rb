# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    PHASE2_BUILDING_TOOL_NAMES = %w[
      create_column
      create_beam
      create_door
      create_window
      apply_material
    ].freeze unless const_defined?(:PHASE2_BUILDING_TOOL_NAMES, false)

    unless private_method_defined?(:handle_tool_call_without_building_elements)
      alias_method :handle_tool_call_without_building_elements, :handle_tool_call
      private :handle_tool_call_without_building_elements
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      return handle_tool_call_without_building_elements(request) unless PHASE2_BUILDING_TOOL_NAMES.include?(tool_name)

      args = request.dig('params', 'arguments') || {}
      architecture_tool_response(request) do
        case tool_name
        when 'create_column'
          create_column(args)
        when 'create_beam'
          create_beam(args)
        when 'create_door'
          create_door(args)
        when 'create_window'
          create_window(args)
        when 'apply_material'
          apply_material(args)
        else
          raise "Unknown Phase 2 building tool: #{tool_name}"
        end
      end
    end

    def create_column(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      center_mm = vector3_numbers(params['center_mm'] || params['center'] || [0, 0, 0], 'center_mm')
      width_mm = positive_number(params['width_mm'] || 400, 'width_mm')
      depth_mm = positive_number(params['depth_mm'] || 400, 'depth_mm')
      height_mm = positive_number(params['height_mm'] || 3000, 'height_mm')
      name = normalized_name(params['name']) || next_entity_name(model, 'Column')

      cx, cy, cz = center_mm
      half_w = width_mm / 2.0
      half_d = depth_mm / 2.0
      base = [
        [mm(cx - half_w), mm(cy - half_d), mm(cz)],
        [mm(cx + half_w), mm(cy - half_d), mm(cz)],
        [mm(cx + half_w), mm(cy + half_d), mm(cz)],
        [mm(cx - half_w), mm(cy + half_d), mm(cz)]
      ]

      model.start_operation('OpenSU: Create Column', true)
      begin
        group = model.entities.add_group
        group.name = name
        add_closed_prism(group.entities, base, mm(height_mm))
        annotate_architecture_entity(
          group,
          'column',
          center_mm: center_mm,
          width_mm: width_mm,
          depth_mm: depth_mm,
          height_mm: height_mm
        )
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      architecture_entity_result(group, 'column', {
        center_mm: center_mm,
        width_mm: width_mm,
        depth_mm: depth_mm,
        height_mm: height_mm
      })
    end

    def create_beam(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      start_mm = vector3_numbers(params['start_mm'] || params['start'], 'start_mm')
      end_mm = vector3_numbers(params['end_mm'] || params['end'], 'end_mm')
      width_mm = positive_number(params['width_mm'] || 300, 'width_mm')
      height_mm = positive_number(params['height_mm'] || 500, 'height_mm')
      name = normalized_name(params['name']) || next_entity_name(model, 'Beam')

      dz = end_mm[2] - start_mm[2]
      raise 'Beam start and end must use the same bottom elevation (z) in Phase 2.' if dz.abs > 0.001

      dx = end_mm[0] - start_mm[0]
      dy = end_mm[1] - start_mm[1]
      length_mm = Math.sqrt((dx * dx) + (dy * dy))
      raise 'Beam start and end must not be the same point.' if length_mm <= 0.001

      half = width_mm / 2.0
      perp_x = (-dy / length_mm) * half
      perp_y = (dx / length_mm) * half
      z = start_mm[2]
      footprint_mm = [
        [start_mm[0] + perp_x, start_mm[1] + perp_y, z],
        [end_mm[0] + perp_x, end_mm[1] + perp_y, z],
        [end_mm[0] - perp_x, end_mm[1] - perp_y, z],
        [start_mm[0] - perp_x, start_mm[1] - perp_y, z]
      ]
      footprint = footprint_mm.map { |point| point.map { |value| mm(value) } }

      model.start_operation('OpenSU: Create Beam', true)
      begin
        group = model.entities.add_group
        group.name = name
        add_closed_prism(group.entities, footprint, mm(height_mm))
        annotate_architecture_entity(
          group,
          'beam',
          start_mm: start_mm,
          end_mm: end_mm,
          length_mm: length_mm,
          width_mm: width_mm,
          height_mm: height_mm
        )
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      architecture_entity_result(group, 'beam', {
        start_mm: start_mm,
        end_mm: end_mm,
        length_mm: length_mm.round(3),
        width_mm: width_mm,
        height_mm: height_mm
      })
    end

    def create_door(params)
      create_opening_assembly(params, 'door')
    end

    def create_window(params)
      create_opening_assembly(params, 'window')
    end

    def create_opening_assembly(params, requested_type)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      wall_id = integer_in_range(params['wall_id'], 'wall_id', 1, 2_147_483_647)
      wall = model.find_entity_by_id(wall_id)
      raise "Wall entity #{wall_id} was not found." unless wall
      raise 'Target entity is not an OpenSU wall Group.' unless wall.is_a?(Sketchup::Group) && wall.get_attribute('OpenSU', 'type') == 'wall'

      openings = parse_wall_openings(wall)
      opening_name = normalized_name(params['opening_name'])
      opening = if opening_name
                  openings.find { |item| item['name'].to_s == opening_name }
                elsif openings.length == 1
                  openings.first
                end
      raise 'No matching opening metadata was found on the target wall.' unless opening

      stored_type = opening['opening_type'].to_s
      if !stored_type.empty? && stored_type != requested_type
        raise "Opening #{opening['name']} is typed as #{stored_type}, not #{requested_type}."
      end

      frame_width_mm = positive_number(params['frame_width_mm'] || 60, 'frame_width_mm')
      wall_thickness_mm = positive_number(wall.get_attribute('OpenSU', 'thickness_mm'), 'stored wall thickness')
      frame_depth_mm = positive_number(params['frame_depth_mm'] || [wall_thickness_mm, 100.0].min, 'frame_depth_mm')
      leaf_depth_mm = positive_number(params['leaf_depth_mm'] || 40, 'leaf_depth_mm')
      glass_thickness_mm = positive_number(params['glass_thickness_mm'] || 8, 'glass_thickness_mm')
      gap_mm = finite_number(params['gap_mm'] || 5, 'gap_mm')
      raise 'gap_mm must be 0 or greater.' if gap_mm.negative?

      offset_mm = positive_number(opening['offset_mm'], 'stored opening offset')
      width_mm = positive_number(opening['width_mm'], 'stored opening width')
      height_mm = positive_number(opening['height_mm'], 'stored opening height')
      sill_mm = finite_number(opening['sill_height_mm'] || 0, 'stored sill height')
      raise 'frame_width_mm is too large for this opening.' if frame_width_mm * 2 >= width_mm
      raise 'frame_width_mm is too large for this opening height.' if frame_width_mm * 2 >= height_mm

      start_mm = JSON.parse(wall.get_attribute('OpenSU', 'start_mm').to_s)
      end_mm = JSON.parse(wall.get_attribute('OpenSU', 'end_mm').to_s)
      basis = wall_basis(start_mm, end_mm)
      name_prefix = requested_type == 'door' ? 'Door' : 'Window'
      assembly_name = normalized_name(params['name']) || next_entity_name(model, name_prefix)

      model.start_operation("OpenSU: Create #{name_prefix}", true)
      begin
        assembly = model.entities.add_group
        assembly.name = assembly_name
        assembly.set_attribute('OpenSU', 'type', requested_type)
        assembly.set_attribute('OpenSU', 'schema_version', 2)
        assembly.set_attribute('OpenSU', 'wall_id', wall.entityID)
        assembly.set_attribute('OpenSU', 'opening_name', opening['name'].to_s)
        assembly.set_attribute('OpenSU', 'frame_width_mm', frame_width_mm)
        assembly.set_attribute('OpenSU', 'frame_depth_mm', frame_depth_mm)

        opening_end = offset_mm + width_mm
        opening_top = sill_mm + height_mm
        frame_side = frame_depth_mm / 2.0
        point = lambda do |along, side, z_offset|
          world_point_mm(start_mm, basis, along, side, z_offset)
        end

        frame_material = ensure_material(model, 'OpenSU_Frame', '#4A4A4A', 1.0)
        create_local_box(assembly.entities, 'Frame_Left', point, offset_mm, offset_mm + frame_width_mm, frame_side, sill_mm, opening_top, frame_material)
        create_local_box(assembly.entities, 'Frame_Right', point, opening_end - frame_width_mm, opening_end, frame_side, sill_mm, opening_top, frame_material)
        create_local_box(assembly.entities, 'Frame_Top', point, offset_mm + frame_width_mm, opening_end - frame_width_mm, frame_side, opening_top - frame_width_mm, opening_top, frame_material)

        if requested_type == 'window'
          create_local_box(assembly.entities, 'Frame_Bottom', point, offset_mm + frame_width_mm, opening_end - frame_width_mm, frame_side, sill_mm, sill_mm + frame_width_mm, frame_material)
          glass_material = ensure_material(model, 'OpenSU_Glass', '#9CC9E8', 0.35)
          glass_side = glass_thickness_mm / 2.0
          glass_z0 = sill_mm + frame_width_mm + gap_mm
          glass_z1 = opening_top - frame_width_mm - gap_mm
          glass_a0 = offset_mm + frame_width_mm + gap_mm
          glass_a1 = opening_end - frame_width_mm - gap_mm
          raise 'Window frame/gap leaves no room for glass.' if glass_z1 <= glass_z0 || glass_a1 <= glass_a0
          create_local_box(assembly.entities, 'Glass', point, glass_a0, glass_a1, glass_side, glass_z0, glass_z1, glass_material)
        else
          leaf_material = ensure_material(model, 'OpenSU_Door', '#8A7764', 1.0)
          leaf_side = leaf_depth_mm / 2.0
          leaf_a0 = offset_mm + frame_width_mm + gap_mm
          leaf_a1 = opening_end - frame_width_mm - gap_mm
          leaf_z0 = sill_mm + gap_mm
          leaf_z1 = opening_top - frame_width_mm - gap_mm
          raise 'Door frame/gap leaves no room for the door leaf.' if leaf_z1 <= leaf_z0 || leaf_a1 <= leaf_a0
          create_local_box(assembly.entities, 'Door_Leaf', point, leaf_a0, leaf_a1, leaf_side, leaf_z0, leaf_z1, leaf_material)
        end

        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        entity_id: assembly.entityID,
        persistent_id: assembly.respond_to?(:persistent_id) ? assembly.persistent_id : nil,
        name: assembly.name.to_s,
        type: requested_type,
        wall_id: wall.entityID,
        wall_name: wall.name.to_s,
        opening_name: opening['name'].to_s,
        bounds_mm: bounds_to_mm(assembly.bounds)
      }
    end

    def apply_material(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      entity_id = integer_in_range(params['entity_id'], 'entity_id', 1, 2_147_483_647)
      entity = model.find_entity_by_id(entity_id)
      raise "Entity #{entity_id} was not found." unless entity

      material_name = normalized_name(params['material_name']) || 'OpenSU_Material'
      color_hex = (params['color_hex'] || '#B8B8B8').to_s
      opacity = finite_number(params.key?('opacity') ? params['opacity'] : 1.0, 'opacity')
      raise 'opacity must be between 0 and 1.' unless opacity.between?(0.0, 1.0)
      recursive = params.key?('recursive') ? !!params['recursive'] : true

      model.start_operation('OpenSU: Apply Material', true)
      begin
        material = ensure_material(model, material_name, color_hex, opacity)
        paint_entity(entity, material, recursive)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        entity_id: entity.entityID,
        name: entity.respond_to?(:name) ? entity.name.to_s : '',
        material_name: material.name,
        color_hex: normalize_hex(color_hex),
        opacity: opacity,
        recursive: recursive
      }
    end

    def parse_wall_openings(wall)
      raw = wall.get_attribute('OpenSU', 'openings_json')
      raise 'Target wall has no opening metadata. Create an opening first.' unless raw

      parsed = JSON.parse(raw.to_s)
      raise 'Target wall opening metadata is not an array.' unless parsed.is_a?(Array)
      parsed
    rescue JSON::ParserError
      raise 'Target wall has invalid opening metadata.'
    end

    def wall_basis(start_mm, end_mm)
      dx = end_mm[0].to_f - start_mm[0].to_f
      dy = end_mm[1].to_f - start_mm[1].to_f
      length = Math.sqrt((dx * dx) + (dy * dy))
      raise 'Stored wall length is invalid.' if length <= 0.001

      {
        ux: dx / length,
        uy: dy / length,
        nx: -dy / length,
        ny: dx / length
      }
    end

    def world_point_mm(start_mm, basis, along, side, z_offset)
      [
        mm(start_mm[0].to_f + (basis[:ux] * along) + (basis[:nx] * side)),
        mm(start_mm[1].to_f + (basis[:uy] * along) + (basis[:ny] * side)),
        mm(start_mm[2].to_f + z_offset)
      ]
    end

    def create_local_box(parent_entities, name, point, along0, along1, side_half, z0, z1, material = nil)
      raise "#{name} has invalid dimensions." unless along1 > along0 && z1 > z0 && side_half.positive?

      child = parent_entities.add_group
      child.name = name
      base = [
        point.call(along0, -side_half, z0),
        point.call(along1, -side_half, z0),
        point.call(along1, side_half, z0),
        point.call(along0, side_half, z0)
      ]
      add_closed_prism(child.entities, base, mm(z1 - z0))
      paint_entity(child, material, true) if material
      child
    end

    def normalize_hex(value)
      text = value.to_s.strip
      text = "##{text}" unless text.start_with?('#')
      raise 'color_hex must use #RRGGBB.' unless text.match?(/^#[0-9A-Fa-f]{6}$/)
      text.upcase
    end

    def ensure_material(model, name, color_hex, opacity)
      hex = normalize_hex(color_hex)
      material = model.materials[name] || model.materials.add(name)
      material.color = Sketchup::Color.new(hex[1, 2].to_i(16), hex[3, 2].to_i(16), hex[5, 2].to_i(16))
      material.alpha = opacity
      material
    end

    def paint_entity(entity, material, recursive)
      entity.material = material if entity.respond_to?(:material=)

      entities = if entity.is_a?(Sketchup::Group)
                   entity.entities
                 elsif entity.is_a?(Sketchup::ComponentInstance)
                   entity.definition.entities
                 end
      return unless entities

      entities.grep(Sketchup::Face).each do |face|
        face.material = material
        face.back_material = material
      end
      return unless recursive

      entities.each do |child|
        next unless child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
        paint_entity(child, material, true)
      end
    end
  end
end
