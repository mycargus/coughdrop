import Ember from 'ember';
import CoughDrop from '../../app';
import i18n from '../../utils/i18n';

export default Ember.Component.extend({
  didInsertElement: function() {
    this.draw();
  },
  elem_class: function() {
    if(this.get('side_by_side')) {
      return Ember.String.htmlSafe('col-sm-6');
    } else {
      return Ember.String.htmlSafe('col-sm-4');
    }
  }.property('side_by_side'),
  elem_style: function() {
    if(this.get('right_side')) {
      return Ember.String.htmlSafe('border-left: 1px solid #eee;');
    } else {
      return Ember.String.htmlSafe('');
    }
  }.property('right_side'),
  draw: function() {
    var stats = this.get('usage_stats');
    var elem = this.get('element').getElementsByClassName('parts_of_speech')[0];

    CoughDrop.Visualizations.wait('pie-chart', function() {
      if(elem && stats && stats.get('parts_of_speech')) {
        var table = [
          ['Task', 'Instances']
        ];
        var parts = stats.get('parts_of_speech');
        var slice_idx = 0;
        var slices = {};
        var color_check = function(c) { return c.types.indexOf(idx) >= 0; };
        for(var idx in parts) {
          table.push([idx, parts[idx]]);
          var color = CoughDrop.keyed_colors.find(color_check);
          slices[slice_idx] = {color: window.tinycolor((color || {fill: "#ccc"}).fill).saturate(10).darken(20).toHexString()};
          slice_idx++;
        }
        var data = window.google.visualization.arrayToDataTable(table);

        var options = {
          slices: slices,
          pieSliceTextStyle: {
            color: '#444'
          },
          chartArea: {
            left: 0,
            top: 0,
            width: '100%',
            height: '100%'
          },
          height: 300
        };


        var chart = new window.google.visualization.PieChart(elem);

        chart.draw(data, options);
      }
    });
  }.observes('usage_stats.draw_id')
});
