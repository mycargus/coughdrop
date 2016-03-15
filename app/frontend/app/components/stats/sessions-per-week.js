import Ember from 'ember';
import CoughDrop from '../../app';
import i18n from '../../utils/i18n';

export default Ember.Component.extend({
  didInsertElement: function() {
    this.draw();
  },
  draw: function() {
    var elem = this.get('element').getElementsByClassName('sessions_per_week')[0];
    var stats = this.get('weekly_stats');

    CoughDrop.Visualizations.wait('bar', function() {
      console.log(stats);
      if(elem && stats) {

        var data = new window.google.visualization.DataTable();
        data.addColumn('date', 'Week Of');
        data.addColumn('number', 'Sessions');

        var rows = [];
        stats.forEach(function(s, index) {
          var m = window.moment(new Date(s.timestamp * 1000));
          rows.push([{v: m._d, f: m.format('MMM DD, YYYY')}, s.sessions]);
        });
        console.log(rows);
        data.addRows(rows);

        var options = {
          colors: ['#f2b367'],
          title: 'Logged User Sessions for the Week',
          legend: {
            position: 'none'
          },
          hAxis: {
            title: 'Week of',
            format: 'MMM dd',
          },
          vAxis: {
            title: 'Total Sessions'
          }
        };

        var chart = new window.google.visualization.ColumnChart(elem);

        chart.draw(data, options);
      }
    });
  }.observes('weekly_stats')
});
