import modal from '../utils/modal';
import app_state from '../utils/app_state';

export default modal.ModalController.extend({
  opening: function() {
    var user = app_state.get('currentUser');
    app_state.set('show_intro', false);
    if(user) {
      user.set('preferences.progress.intro_watched', true);
      user.save().then(null, function() { });
    }
    this.set('page', 1);
    this.set('total_pages', 14);
    if(window.ga) {
      window.ga('send', 'event', 'Intro', 'start', 'Intro Modal Opened');
    }
  },
  set_pages: function() {
    var page = this.get('page');
    this.set('pages', {});
    this.set('pages.page_' + page, true);
    this.set('pages.last_page', page == this.get('total_pages'));
    this.set('pages.first_page', page == 1);
  }.observes('page'),
  actions: {
    next: function() {
      var page = this.get('page') || 1;
      page++;
      if(page > this.get('total_pages')) { page = this.get('total_pages'); }
      this.set('page', page);
    },
    previous: function() {
      var page = this.get('page') || 1;
      page--;
      if(page < 1) { page = 1; }
      this.set('page', page);
    },
    video: function() {
      if(window.ga) {
        window.ga('send', 'event', 'Intro', 'video', 'Intro Video Opened');
      }
      modal.open('inline-video', {video: {url: "https://www.youtube.com/embed/gsxfLVhUbus?rel=0"}, hide_overlay: true});
    }
  }
});
