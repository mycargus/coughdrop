import Ember from 'ember';
import persistence from '../utils/persistence';

export default Ember.Route.extend({
  setupController: function(controller) {
    var _this = this;
    function loadBoards() {
      if(persistence.get('online')) {
        controller.set('home_boards', {loading: true});
        _this.store.query('board', {user_id: 'example', starred: true, public: true}).then(function(boards) {
          controller.set('home_boards', boards);
        }, function() {
          controller.set('home_boards', null);
        });
        controller.set('core_vocabulary', {loading: true});
        _this.store.query('board', {user_id: 'example', starred: true, public: true, per_page: 6}).then(function(boards) {
          controller.set('core_vocabulary', boards);
        }, function() {
          controller.set('core_vocabulary', null);
        });
        controller.set('subject_vocabulary', {loading: true});
        _this.store.query('board', {user_id: 'subjects', starred: true, public: true, per_page: 6}).then(function(boards) {
          controller.set('subject_vocabulary', boards);
        }, function() {
          return Ember.RSVP.resolve({});
        });
//         controller.set('disability_vocabulary', {loading: true});
//         _this.store.query('board', {user_id: 'disability_boards', starred: true, public: true}).then(function(boards) {
//           controller.set('disability_vocabulary', boards);
//         }, function() {
//           controller.set('disability_vocabulary', null);
//         });
      } else {
        controller.set('home_boards', null);
        controller.set('core_vocabulary', null);
        controller.set('subject_vocabulary', null);
        controller.set('disability_vocabulary', null);
      }
    }
//     loadBoards();
//     persistence.addObserver('online', function() {
//       loadBoards();
//     });
  }
});
