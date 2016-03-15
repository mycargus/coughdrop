import Ember from 'ember';
import CoughDrop from '../../app';
import i18n from '../../utils/i18n';

export default Ember.Component.extend({
  didInsertElement: function() {
    this.draw();
  },
  draw: function() {
    var total = this.get('total');
    var recent = this.get('recent');
    var elem = this.get('element').getElementsByClassName('recent_sessions')[0];

    CoughDrop.Visualizations.wait('pie-chart', function() {
      if(elem && total) {
        var table = [
          ['Type', 'Total']
        ];
        var not_recent = total - recent;
        table.push(["Users with Session(s) in Last 2 Weeks", recent]);
        table.push(["No Recent Sessions", not_recent]);
        var data = window.google.visualization.arrayToDataTable(table);

        var options = {
          slices: {
            0: {color: "#49c7e8"},
            1: {color: "#f7483b"}
          }
        };

        var chart = new window.google.visualization.PieChart(elem);
        chart.draw(data, options);
      }
    });
  }.observes('total', 'recent')
});
