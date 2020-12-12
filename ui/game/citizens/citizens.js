App.StonehearthCitizensView.reopen({
   
   didInsertElement: function() {
      var self = this;
      self._super();

      this.$('#promote_to_job').remove();
   }
});
