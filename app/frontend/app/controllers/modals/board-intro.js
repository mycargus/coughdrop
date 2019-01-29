import modal from '../../utils/modal';
import app_state from '../../utils/app_state';
import utterance from '../../utils/utterance';
import RSVP from 'rsvp';

export default modal.ModalController.extend({
  opening: function() {
    // which step are we on?
    var step = this.get('model.step') || 0;
    this.set('current_step', (this.get('model.board.intro.sections') || [])[step]);
    var user = app_state.get('currentUser');
    var intros = app_state.get('currentUser.preferences.progress.board_intros') || [];
    intros.push(this.get('model.board.id'));
    if(user) {
      user.set('preferences.progress.board_intros', intros);
      user.save();
    }
  },
  next_step: function() {
    var step = (this.get('model.step') || 0);
    var section = (this.get('model.board.intro.sections') || [])[step];
    return !!section;
  }.property('model.step'),
  actions: {
    close: function() {
      // clear step and modal.close
      modal.close();
    },
    next: function() {
      var step = (this.get('model.step') || 0) + 1;
      var section = this.get('model.board.intro.sections')[step];
      this.set('current_step', section);
      if(section) {
        this.set('model.step', step);
      }
    },
    start: function() {
      var board = this.get('model.board');
      var _this = this;
      if(!this.get('current_step.prompt')) {
        this.send('next');
        return;
      }
      if(board.get('button_set')) {
        var user = app_state.get('currentUser');
        var search = null;
        var search = board.get('button_set').find_sequence(_this.get('current_step.prompt'), board.get('id'), user, false);
        var show_sequence = function(result) {
          var buttons = result.pre_buttons || [];
          if(result.pre_action == 'home') {
            buttons.unshift('home');
          }
          if(result.sequence) {
            result.steps.forEach(function(step) {
              if(step.sequence.pre == 'true_home') {
                buttons.push({pre: 'true_home'});
              }
              step.sequence.buttons.forEach(function(btn) {
                buttons.push(btn);
              });
              buttons.push(step.button);
            });
          } else {
            buttons.push(result);
          }

          app_state.controller.highlight_button(buttons, board.get('button_set')).then(function() {
            utterance.clear();
            // re-open the modal at the next step
            modal.open('modals/board-intro', {board: _this.get('model.board'), step: (_this.get('model.step') + 1)});
          }, function() {
            // should only happen if the user cancels out of the help
            debugger
          });
        };
        search.then(function(results) {
          if(window.persistence.get('online')) {
            show_sequence(results[0]);
          } else {
            var new_results = [];
            var promises = [];
            results.forEach(function(b) {
              var images = [b.image];
              if(b.sequence) {
                images = b.steps.map(function(s) { return s.button.image; });
              }
              var missing_image = images.find(function(i) { return !i || i.match(/^http/); });
              if(!missing_image) {
                new_results.push(b);
              } else { }
            });
            RSVP.all_wait(promises).then(null, function() { return RSVP.resolve(); }).then(function() {
              show_sequence(new_results[0]);
            });
          }
        }, function(err) {
          alert('nopety nope');
        });
      } else {
        alert('nopety nope');
      }
    }
  }
});
