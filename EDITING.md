# Editing
We use Audacity for editing, then GarageBand for putting it all together.
But before that, we'll need to grab the audio files from Cast.

## Cast
- Export the audio tracks from Cast (you can find them in the profile)

## Audacity
- Import the audio tracks in Audacity

### Noise Reduction
- For noise reduction, select a silenced part (separately for all tracks),
and:
  - Go to `Effects` > `Noise Reduction` > Click `Get Noise Profile`.
  - Select the whole track for which the silenced part was selected (double
  click on the track), go to `Effects` > `Noise Reduction` > `OK`
  - Repeat for all tracks.

### Silencing
- To cut out sound from a particular track (i.e. in case of overlaps):
  - Select the part, `Effects` > `Amplify` > turn it all the way to the left.

### Clipping Spikes
- To clip spikes in audio levels:
  - Select a spike, `Effects` > `Amplify` > turn it a bit to the left. This is
  a bit of trial and error. You can start with e.g. `-3.0`.

### Amplify Unification
- After clipping spikes, if the waves are still different in height:
  - Select the track with the larger waves, `Effects` > `Amplify` and make the
  wave length the same (similar to clipping a spike).

### Finishing up in Audacity
- Export as WAV > chose AIFF.
