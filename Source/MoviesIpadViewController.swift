//
//  Copyright (c) 2016 Algolia
//  http://www.algolia.com/
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import AlgoliaSearch
import InstantSearchCore
import TTRangeSlider
import UIKit

class MoviesIpadViewController: UIViewController, UICollectionViewDataSource, TTRangeSliderDelegate, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate, SearchProgressDelegate {
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var genreTableView: UITableView!
    @IBOutlet weak var yearRangeSlider: TTRangeSlider!
    @IBOutlet weak var ratingSelectorView: RatingSelectorView!
    @IBOutlet weak var moviesCollectionView: UICollectionView!
    @IBOutlet weak var moviesCollectionViewPlaceholder: UILabel!
    @IBOutlet weak var actorsTableView: UITableView!
    @IBOutlet weak var movieCountLabel: UILabel!
    @IBOutlet weak var searchTimeLabel: UILabel!
    @IBOutlet weak var genreTableViewFooter: UILabel!
    @IBOutlet weak var genreFilteringModeSwitch: UISwitch!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!

    var actorSearcher: Searcher!
    var movieSearcher: Searcher!
    var actorHits: [JSONObject] = []
    var movieHits: [JSONObject] = []
    var strategist: SearchStrategist!
    var genreFacets: [FacetValue] = []

    var yearFilterDebouncer = Debouncer(delay: 0.3)
    var searchProgressController: SearchProgressController!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.movieCountLabel.text = NSLocalizedString("movie_count_placeholder", comment: "")
        self.searchTimeLabel.text = nil

        // Customize search bar.
        searchBar.placeholder = NSLocalizedString("search_bar_placeholder", comment: "")
        searchBar.enablesReturnKeyAutomatically = false

        // Customize year range slider.
        yearRangeSlider.numberFormatterOverride = NumberFormatter()
        let tintColor = self.view.tintColor
        yearRangeSlider.tintColorBetweenHandles = tintColor
        yearRangeSlider.handleColor = tintColor
        yearRangeSlider.lineHeight = 3
        yearRangeSlider.minLabelFont = UIFont.systemFont(ofSize: 12)
        yearRangeSlider.maxLabelFont = yearRangeSlider.minLabelFont

        ratingSelectorView.addObserver(self, forKeyPath: "rating", options: .new, context: nil)

        // Customize genre table view.
        genreTableView.tableFooterView = genreTableViewFooter
        genreTableViewFooter.isHidden = true

        // Configure actor search.
        actorSearcher = Searcher(index: AlgoliaManager.sharedInstance.actorsIndex, resultHandler: self.handleActorSearchResults)
        actorSearcher.params.hitsPerPage = 10
        actorSearcher.params.attributesToHighlight = ["name"]

        // Configure movie search.
        movieSearcher = Searcher(index: AlgoliaManager.sharedInstance.moviesIndex, resultHandler: self.handleMovieSearchResults)
        movieSearcher.params.facets = ["genre"]
        movieSearcher.params.attributesToHighlight = ["title"]
        movieSearcher.params.hitsPerPage = 30

        NotificationCenter.default.addObserver(self, selector: #selector(self.updatePlaceholder), name: Searcher.SearchNotification, object: movieSearcher)

        // Configure search progress monitoring.
        searchProgressController = SearchProgressController(searcher: movieSearcher)
        searchProgressController.graceDelay = 0.5
        searchProgressController.delegate = self

        strategist = SearchStrategist()
        strategist.addSearcher(movieSearcher)
        strategist.addSearcher(actorSearcher)
        strategist.addObserver(self, forKeyPath: "strategy", options: .New, context: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.requestDropped), name: SearchStrategist.DropNotification, object: strategist)
        
        updateMovies()
        search()

        // Start a sync if needed.
        AlgoliaManager.sharedInstance.syncIfNeededAndPossible()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: - State update
    
    private func updateMovies() {
        moviesCollectionViewPlaceholder.hidden = !movieHits.isEmpty
        if movieHits.isEmpty {
            moviesCollectionViewPlaceholder.text = "No results"
        }
        moviesCollectionView.reloadData()
    }
    
    private func updateStatusLabelColor() {
        switch strategist.strategy {
        case .Realtime: searchTimeLabel.textColor = UIColor.greenColor(); break
        case .Throttled: searchTimeLabel.textColor = UIColor.purpleColor(); break
        case .Manual: searchTimeLabel.textColor = UIColor.orangeColor(); break
        }
    }

    // MARK: - Actions

    private func search(asYouType: Bool = false) {
        movieSearcher.params.setFacet(withName: "genre", disjunctive: genreFilteringModeSwitch.isOn)
        movieSearcher.params.clearNumericRefinements()
        movieSearcher.params.addNumericRefinement("year", .greaterThanOrEqual, Int(yearRangeSlider.selectedMinimum))
        movieSearcher.params.addNumericRefinement("year", .lessThanOrEqual, Int(yearRangeSlider.selectedMaximum))
        movieSearcher.params.addNumericRefinement("rating", .greaterThanOrEqual, ratingSelectorView.rating)
        strategist.search(asYouType)
    }

    @IBAction func genreFilteringModeDidChange(_ sender: AnyObject) {
        movieSearcher.params.setFacet(withName: "genre", disjunctive: genreFilteringModeSwitch.isOn)
        search()
    }

    @IBAction func configTapped(_ sender: AnyObject) {
        let vc = ConfigViewController(nibName: "ConfigViewController", bundle: nil)
        self.present(vc, animated: true, completion: nil)
    }

    // MARK: - UISearchBarDelegate

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        actorSearcher.params.query = searchText
        movieSearcher.params.query = searchText
        search(true)
    }
    
    func searchBarSearchButtonClicked(searchBar: UISearchBar) {
        search()
    }
    
    // MARK: - Search completion handlers

    private func handleActorSearchResults(results: SearchResults?, error: Error?) {
        guard let results = results else { return }
        if results.page == 0 {
            actorHits = results.hits
        } else {
            actorHits.append(contentsOf: results.hits)
        }
        self.actorsTableView.reloadData()

        // Scroll to top.
        if results.page == 0 {
            self.moviesCollectionView.contentOffset = CGPoint.zero
        }
    }

    private func handleMovieSearchResults(results: SearchResults?, error: Error?) {
        guard let results = results else {
            self.searchTimeLabel.textColor = UIColor.red
            self.searchTimeLabel.text = NSLocalizedString("error_search", comment: "")
            return
        }
        if results.page == 0 {
            movieHits = results.hits
        } else {
            movieHits.append(contentsOf: results.hits)
        }
        // Sort facets: first selected facets, then by decreasing count, then by name.
        genreFacets = FacetValue.listFrom(facetCounts: results.facets(name: "genre"), refinements: movieSearcher.params.buildFacetRefinements()["genre"]).sorted() { (lhs, rhs) in
            // When using cunjunctive faceting ("AND"), all refined facet values are displayed first.
            // But when using disjunctive faceting ("OR"), refined facet values are left where they are.
            let disjunctiveFaceting = results.disjunctiveFacets.contains("genre")
            let lhsChecked = self.movieSearcher.params.hasFacetRefinement(name: "genre", value: lhs.value)
            let rhsChecked = self.movieSearcher.params.hasFacetRefinement(name: "genre", value: rhs.value)
            if !disjunctiveFaceting && lhsChecked != rhsChecked {
                return lhsChecked
            } else if lhs.count != rhs.count {
                return lhs.count > rhs.count
            } else {
                return lhs.value < rhs.value
            }
        }
        let exhaustiveFacetsCount = results.exhaustiveFacetsCount == true
        genreTableViewFooter.isHidden = exhaustiveFacetsCount

        let formatter = NumberFormatter()
        formatter.locale = NSLocale.current
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        self.movieCountLabel.text = "\(formatter.string(for: results.nbHits)!) MOVIES"

        updateStatusLabelColor()
        self.searchTimeLabel.text = "Found in \(results.processingTimeMS) ms"
        // Indicate origin of content.
        if results.content["origin"] as? String == "local" {
            searchTimeLabel.text! += " (offline results)"
        }

        self.genreTableView.reloadData()
        updateMovies()

        // Scroll to top.
        if results.page == 0 {
            self.moviesCollectionView.contentOffset = CGPoint.zero
        }
    }

    // MARK: - UICollectionViewDataSource

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return movieHits.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "movieCell", for: indexPath) as! MovieCell
        cell.movie = MovieRecord(json: movieHits[indexPath.item])
        if indexPath.item + 5 >= movieHits.count {
            movieSearcher.loadMore()
        }
        return cell
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch tableView {
            case actorsTableView: return actorHits.count
            case genreTableView: return genreFacets.count
            default: assert(false); return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch tableView {
            case actorsTableView:
                let cell = tableView.dequeueReusableCell(withIdentifier: "actorCell", for: indexPath) as! ActorCell
                cell.actor = Actor(json: actorHits[indexPath.item])
                if indexPath.item + 5 >= actorHits.count {
                    actorSearcher.loadMore()
                }
                return cell
            case genreTableView:
                let cell = tableView.dequeueReusableCell(withIdentifier: "genreCell", for: indexPath) as! GenreCell
                cell.value = genreFacets[indexPath.item]
                cell.checked = movieSearcher.params.hasFacetRefinement(name: "genre", value: genreFacets[indexPath.item].value)
                return cell
            default: assert(false); return UITableViewCell()
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch tableView {
            case genreTableView:
                movieSearcher.params.toggleFacetRefinement(name: "genre", value: genreFacets[indexPath.item].value)
                strategist.search(false)
                break
            default: return
        }
    }

    // MARK: - TTRangeSliderDelegate

    func rangeSlider(_ sender: TTRangeSlider!, didChangeSelectedMinimumValue selectedMinimum: Float, andMaximumValue selectedMaximum: Float) {
        yearFilterDebouncer.call {
            self.search(false)
        }
    }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let object = object as? NSObject else { return }
        if object === ratingSelectorView {
            if keyPath == "rating" {
                search()
            }
        } else if object === strategist {
            if keyPath == "strategy" {
                guard let strategy = change?[NSKeyValueChangeNewKey] as? Int else { return }
                searchTimeLabel.text = "New strategy: \(strategy)"
                updateStatusLabelColor()
            }
        }
    }

    // MARK: - SearchProgressDelegate
    
    func searchDidStart(_ searchProgressController: SearchProgressController) {
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
    }
    
    func searchDidStop(_ searchProgressController: SearchProgressController) {
        UIApplication.shared.isNetworkActivityIndicatorVisible = false
        activityIndicator.stopAnimating()
    }

    // MARK: - Events
    
    @objc private func requestDropped(notification: NSNotification) {
        // Now that we have dropped a request, we should not display any results, as they won't correspond to the
        // last entered text. => Cancel all pending requests.
        movieSearcher.cancelPendingRequests()
        actorHits.removeAll()
        movieHits.removeAll()
        actorsTableView.reloadData()
        updateMovies()
        moviesCollectionViewPlaceholder.text = "Press “Search” to see results…"
    }
    
    @objc private func updatePlaceholder(notification: NSNotification) {
        if notification.name == Searcher.SearchNotification {
            moviesCollectionViewPlaceholder.text = "Searching…"
        }
    }
}
