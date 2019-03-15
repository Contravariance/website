<p align="center">
  <strong>Listen on <a href="https://itunes.apple.com/us/podcast/contravariance-a-swift-podcast/id1423771323">iTunes</a> | <a href="https://overcast.fm/itunes1423771323/contravariance-a-swift-podcast">Overcast</a> | <a href="https://pca.st/QjR1">Pocket Casts</a></strong>
</p>
<p align="center">
  <img src="material/logo_big.jpg" alt="Contravariance Podcast logo" width="350">
</p>

# Contravariance
### https://contravariance.rocks

Contravariance is a podcast by [Benedikt Terhechte](https://twitter.com/terhechte) and [Bas Broek](https://twitter.com/BasThomas) about Apple, Swift and other programming topics.

The podcast's website, feed and artwork material can be found in this repository.

# Building the Site

```
./masse.swift ./config.bacf
```

# Adding a new episode

This uses [Satokoda](https://github.com/terhechte/Satokoda) to write 
the `ID3` tags into the mp3. To simplify things, it has been added
to the repository as a binary.

1. Place mp3 file in `episodes`
2. Go into the `material` folder (in terminal)
3. Run `satokoda` as follows (example filename)

``` bash
./satokoda -f ../episodes/203_documentation.mp3 -t "203: Documentation" -c ./config.toml
```
