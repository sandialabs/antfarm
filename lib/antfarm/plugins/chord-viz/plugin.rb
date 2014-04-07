# Using a Chord Diagram to display traffic captures

# Each edge of the circle is a node (src/dst) in the network
#   Create CSV list of src/dst nodes
# Each chord represents traffic between nodes
#   Create matrix of data, each row containing count of connections
#   between src/dst paiattr_reader :attr_namess

module Antfarm
  module ChordViz
    class Env
      attr_accessor :cities
      attr_accessor :matrix
    end

    def self.registered(plugin)
      plugin.name = 'chord-viz'
      plugin.info = {
        :desc   => 'Visualize network traffic in DB as a diagram graph w/ D3js',
        :author => 'Bryan T. Richardson'
      }
      plugin.options = [{
        :name    => 'file_name',
        :desc    => 'Name to use for output file (will land in ~/.antfarm/tmp)',
        :type    => String,
        :default => 'chord.html'
      }]
    end

    def run(opts = Hash.new)
      check_options(opts)

      csv = Hash.new # poor man's unique Set...

      Antfarm::Models::Connection.all.each do |conn|
        csv[conn.src_id] = true
        csv[conn.dst_id] = true
      end

      nodes  = csv.keys.sort
      matrix = Array.new(nodes.size) { Array.new(nodes.size, 0) }

      Antfarm::Models::Connection.all.each do |conn|
        i = nodes.index(conn.src_id)
        j = nodes.index(conn.dst_id)

        matrix[i][j] += 1
      end

      cities = Array.new(nodes.size)
      nodes.each_with_index do |node,index|
        name = Antfarm::Models::L3If.find(node).l2_if.node.id

        cities[index] = { :name => name, :color => random_color_code }
      end

      env        = Env.new
      env.cities = cities.to_json
      env.matrix = matrix.to_json

      # Alternative to using DATA, since it won't work in required files...
      # TODO: turn this into a helper available from the Plugin parent class
      template = File.read(__FILE__) =~ /^__END__\n/ && $' || ''
      content  = Slim::Template.new { template }

      File.open("#{Antfarm::Helpers.user_tmp_dir}/#{opts[:file_name]}", 'w') do |f|
        f.write(content.render(env))
      end

      # TODO: how to make this more cross-platform... Launchy gem perhaps?!
      `open #{Antfarm::Helpers.user_tmp_dir}/#{opts[:file_name]}`
    end

    def random_color_code
      lum, ary = 0, []

      while lum < 128
       ary = (1..3).collect {rand(256)}
       lum = ary[0]*0.2126 + ary[1]*0.7152 + ary[2]*0.0722
      end

      return "##{ary.collect { |e| e.to_s(16) }.join}"
    end
  end
end

Antfarm.register(Antfarm::ChordViz)

__END__

doctype html
html
  head
    title Chord Diagram
    meta  charset="UTF-8"
    css:
      #circle circle {
        fill: none;
        pointer-events: all;
      }

      .group path {
        fill-opacity: .5;
      }

      path.chord {
        stroke: #000;
        stroke-width: .25px;
      }

      #circle:hover path.fade {
        display: none;
      }

  body
    script src="http://d3js.org/d3.v3.min.js"

    javascript:
      var width  = 720,
          height = 720,
          outerRadius = Math.min(width, height) / 2 - 10,
          innerRadius = outerRadius - 24;

      var cities = #{{cities}};
      var matrix = #{{matrix}};

      var formatPercent = d3.format(".1%");

      var arc = d3.svg.arc()
          .innerRadius(innerRadius)
          .outerRadius(outerRadius);

      var layout = d3.layout.chord()
          .padding(.04)
          .sortSubgroups(d3.descending)
          .sortChords(d3.ascending);

      var path = d3.svg.chord()
          .radius(innerRadius);

      var svg = d3.select("body").append("svg")
          .attr("width", width)
          .attr("height", height)
          .append("g")
          .attr("id", "circle")
          .attr("transform", "translate(" + width / 2 + "," + height / 2 + ")");

      svg.append("circle")
          .attr("r", outerRadius);

      // Compute the chord layout.
      layout.matrix(matrix);

      // Add a group per neighborhood.
      var group = svg.selectAll(".group")
          .data(layout.groups)
          .enter().append("g")
          .attr("class", "group")
          .on("mouseover", mouseover);

      // Add a mouseover title.
      //group.append("title").text(function(d, i) {
      //  return cities[i].name + ": " + formatPercent(d.value) + " of origins";
      //});

      // Add the group arc.
      var groupPath = group.append("path")
          .attr("id", function(d, i) { return "group" + i; })
          .attr("d", arc)
          .style("fill", function(d, i) { return cities[i].color; });

      // Add a text label.
      var groupText = group.append("text")
          .attr("x", 6)
          .attr("dy", 15);

      groupText.append("textPath")
          .attr("xlink:href", function(d, i) { return "#group" + i; })
          .text(function(d, i) { return cities[i].name; });

      // Remove the labels that don't fit. :(
      groupText.filter(function(d, i) { return groupPath[0][i].getTotalLength() / 2 - 16 < this.getComputedTextLength(); })
          .remove();

      // Add the chords.
      var chord = svg.selectAll(".chord")
          .data(layout.chords)
          .enter().append("path")
          .attr("class", "chord")
          .style("fill", function(d) { return cities[d.source.index].color; })
          .attr("d", path);

      // Add an elaborate mouseover title for each chord.
      //chord.append("title").text(function(d) {
      //  return cities[d.source.index].name
      //      + " → " + cities[d.target.index].name
      //      + ": " + formatPercent(d.source.value)
      //      + "\n" + cities[d.target.index].name
      //      + " → " + cities[d.source.index].name
      //      + ": " + formatPercent(d.target.value);
      //});

      function mouseover(d, i) {
        chord.classed("fade", function(p) {
          return p.source.index != i
              && p.target.index != i;
        });
      }
