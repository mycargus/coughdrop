import Ember from 'ember';

export default Ember.Component.extend({
  tagName: 'span',
  protected_license: function() {
    return this.get('license.protected');
  }.property('license.protected'),
  private_license: function() {
    return this.get('license.type') == 'private';
  }.property('license.type')
});
