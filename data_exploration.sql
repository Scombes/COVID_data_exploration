USE covid;

/*
Covid 19 Data Exploration 

	Skills used: Joins, CTE's, Temp Tables, Windows Functions, Aggregate Functions, Creating Views

	Used data from Our World In Data and created 3 tables:
		- cases_deaths : Contains data relating to covid cases and death around the world
		- vaccinations:  Contains data relating to vacine rates around the world
		- demographics: Contains demographic data for each country in other two tables
    
    Link to Tableau Dashboard: https://tabsoft.co/3Fiuh8w
    
*/


-- LOOKING AT NUMBERS GLOBABLY

/* 
	Daily totals for population, cases, deaths and vaccinations globally
*/

SELECT 
    cd.record_date,
    SUM(demo.population) AS total_population,
    SUM(cd.new_cases) AS total_cases,
    SUM(cd.new_deaths) AS total_deaths,
    SUM(cv.people_vaccinated) AS total_vaccinated
FROM
    cases_deaths cd
        JOIN
    vaccinations cv ON cv.location = cd.location
        AND cv.record_date = cd.record_date
        JOIN
    demographics demo ON demo.location = cd.location
        AND demo.record_date = cd.record_date
WHERE
    cd.continent IS NOT NULL
GROUP BY 1
ORDER BY 1
;


-- LOOKING AT GENERAL NUMBERS BY COUNTRY

/*
	Daily total population, cases, deaths and vaccinations by Country
*/

SELECT
	cd.record_date,
    cd.location,
    cd.new_cases AS daily_cases,
    cd.new_deaths AS daily_deaths,
    vax.new_vaccinations AS daily_vaccinations
FROM cases_deaths cd
LEFT JOIN vaccinations vax
	ON vax.location = cd.location AND vax.record_date = cd.record_date
LEFT JOIN demographics demo ON demo.location = cd.location AND demo.record_date = cd.record_date
WHERE cd.continent IS NOT NULL
;


/*
	Total Cases vs Total Deaths
    - Shows the liklihood of dying if you contract covid in each country
*/

SELECT
	location,
    record_date,
    total_cases,
    total_deaths,
    (total_deaths/total_cases)*100 AS death_percentage
FROM cases_deaths
WHERE continent IS NOT NULL
ORDER BY 1,2
;


/* 
	Cases & Deaths Relative to Population: Cumlative by Country
	- Shows the number of cases and deaths per million people
*/

SELECT
    cd.location,
    demo.population,
    MAX(cd.total_cases) AS total_cases,
    MAX(cd.total_cases)*1000000 / demo.population AS cases_per_million,
    MAX(cd.total_deaths) AS total_deaths,
    MAX(cd.total_deaths)*1000000 /  demo.population AS deaths_per_million
FROM cases_deaths cd
LEFT JOIN vaccinations vax
	ON vax.location = cd.location AND vax.record_date = cd.record_date
LEFT JOIN demographics demo ON demo.location = cd.location AND demo.record_date = cd.record_date
WHERE cd.continent IS NOT NULL
GROUP BY 1, 2
ORDER BY 1
;


/*
	Total Cases vs Population
	- Shows what percentage of population infected with covid
*/

SELECT 
    cd.location,
    cd.record_date,
    demo.population,
    cd.total_cases,
    (cd.total_cases / demo.population) * 100 AS pct_population_infected
FROM
    cases_deaths cd
        LEFT JOIN
    demographics demo ON demo.location = cd.location
        AND demo.record_date = cd.record_date
WHERE
    cd.continent IS NOT NULL
ORDER BY 1 , 2
;


/* 
	Vacination Rates
	- The percentage of the population who has received at least one does
      of the covid vaccine
*/

SELECT 
    MAX(vax.record_date) AS latest_date,
    vax.location,
    demo.population,
    MAX(people_vaccinated) AS total_vaxed,
    (MAX(people_vaccinated) / demo.population) * 100 AS pct_population_vaxed
FROM
    vaccinations vax
        JOIN
    demographics demo ON demo.location = vax.location
        AND demo.record_date = vax.record_date
WHERE
    vax.continent IS NOT NULL
GROUP BY 2 , 3
;

-- Creating a View to store data for later use

CREATE VIEW PercentPopulationVaccinated AS
SELECT 
    MAX(vax.record_date) AS latest_date,
    vax.location,
    demo.population,
    MAX(people_vaccinated) AS total_vaxed,
    (MAX(people_vaccinated) / demo.population) * 100 AS pct_population_vaxed
FROM
    vaccinations vax
        JOIN
    demographics demo ON demo.location = vax.location
        AND demo.record_date = vax.record_date
WHERE
    vax.continent IS NOT NULL
GROUP BY 2 , 3
;


-- BREAKING THINGS DOWN BY CONTINENT

/* 
	Countinents with highest death count per population
	- Find the MAX total deaths for each country & group by continent, location
	- Use as a subquery to SUM total death count and group by continent
*/

SELECT 
    continent, SUM(total_death_count) AS total_death_count
FROM
    (SELECT 
        continent,
            location,
            MAX(total_deaths) AS total_death_count
    FROM
        cases_deaths
    WHERE
        continent IS NOT NULL
    GROUP BY 1 , 2
    ORDER BY 1 , 2) AS tbl
GROUP BY 1
ORDER BY 2 DESC
;

/*
	Cases & Deaths Per Million by Continent
    -- Breakdown by Month
    -- First get total cases, deaths and population per month for each country
    -- Use as a CTE to get cases and deaths per million for each continent
*/

WITH country_monthly_numbers AS
(SELECT 
       YEAR( cd.record_date) AS yr,
       MONTH( cd.record_date) AS mo,
		cd.continent,
		cd.location,
        demo.population,
		MAX(total_cases) AS total_cases_per_month,
		MAX(total_deaths) AS total_deaths_per_month
    FROM
        cases_deaths cd
    JOIN demographics demo ON demo.location = cd.location
        AND demo.record_date = cd.record_date
    WHERE
        cd.continent IS NOT NULL
    GROUP BY 1 , 2 , 3, 4, 5)
SELECT
	yr,
    mo,
    continent,
    SUM(population) AS population,
    SUM(total_cases_per_month)*1000000 / SUM(population) AS cases_per_million,
    SUM(total_deaths_per_month)*1000000 / SUM(population) AS deaths_per_million
FROM country_monthly_numbers
GROUP BY 1, 2, 3
;


-- ADVANCED ANALYSIS

/* 
	Latest Vacination Rates: Globally
    - Total doses given worldwide
    - Change since previous day
    - Number of people fully vaccinated
    - Percent of population fully vaccinated
*/
 -- Create a variable that stores the total world population
SET @world_population = 
	(SELECT 
		SUM(demo.population)
	FROM
		demographics demo
	WHERE
		continent IS NOT NULL
	GROUP BY demo.record_date
	ORDER BY 1 DESC
	LIMIT 1);				

-- Since there is a location for World figures we can use that to pull in the needed vaccine numbers.
-- Get record_date, location, total_vaccinations and people_fully_vaccinated for world location
-- Use a window function to get previous days total vaccinations and subtract from todays vaccinations
-- Divide people_fully_vaccinated by world_population variable and multiply by 100 to get pct_population_fully_vaccinated
SELECT
    vax.record_date,
    vax.location,
    total_vaccinations,
	total_vaccinations - LAG(total_vaccinations) OVER (Partition by vax.location ORDER BY vax.location, vax.record_date) AS change_in_vax,
	people_fully_vaccinated,
   (people_fully_vaccinated / @world_population)*100 AS pct_population_fully_vaxed
FROM vaccinations vax
LEFT JOIN demographics demo ON demo.location = vax.location AND demo.record_date = vax.record_date
WHERE vax.location = 'World'
ORDER BY 1 DESC
LIMIT 1
;


/* 
	Quarter Over Quarter Change for Cases and Deaths Globaly
    - Get total cases and deaths per million. Group by year and quarter
    - Use as CTE
    - Use window functions to get previous quarter numbers
    - Quarter over Quarter change = (Current quarter - previous quarter)/ previous quarter
*/

WITH cte AS 
	(SELECT
        YEAR(record_date) AS yr,
        QUARTER(record_date) AS qrt,
		SUM(new_cases)*1000000 / 7983533750 AS total_cases_per_million,
		SUM(new_deaths)*1000000 / 7983533750 AS total_deaths_per_million
	FROM cases_deaths
	WHERE continent IS NOT NULL
	GROUP BY 1,2 
	ORDER BY 1, 2 )
SELECT
    CONCAT(yr, "-","Q", qrt) AS qrt,
    total_cases_per_million,
    LAG(total_cases_per_million) OVER (ORDER BY yr, qrt) AS previous_qrt_cases,
    (total_cases_per_million - LAG(total_cases_per_million) OVER (ORDER BY yr, qrt)) /  LAG(total_cases_per_million) OVER (ORDER BY yr, qrt) AS pct_change_cases,
    total_deaths_per_million,
    LAG(total_deaths_per_million) OVER (ORDER BY yr, qrt) AS previous_qrt_deaths,
    (total_deaths_per_million - LAG(total_deaths_per_million) OVER (ORDER BY yr, qrt)) /  LAG(total_deaths_per_million) OVER (ORDER BY yr, qrt) AS pct_change_deaths
FROM cte
;
    


/*
	Total Cases and deaths compared to GDP Per Capita  
    - Sort countries into buckets based on GDP Per Capita
		- <10k
        - 10k - 20k
        - 20k - 30k
        - 30k - 40k
        - >40k
	- Determin cases and deaths per million for each bucket
    - Count how many countries are in each bucket
*/

WITH country_cases_gdp AS
(SELECT
	cd.location,
    demo.population, 
    demo.gdp_per_capita,
    SUM(cd.new_cases)*1000000 / demo.population AS total_cases_per_million,
    SUM(cd.new_deaths)*1000000 / demo.population AS total_deaths_per_million,
    CASE 
		WHEN demo.gdp_per_capita < 10000 THEN '<10k'
        WHEN demo.gdp_per_capita >= 10000 AND demo.gdp_per_capita < 20000  THEN '10k - 20k'
		WHEN demo.gdp_per_capita >= 20000 AND demo.gdp_per_capita < 30000  THEN '20k - 30k'
        WHEN demo.gdp_per_capita >= 30000 AND demo.gdp_per_capita < 40000  THEN '30k - 40k'
		WHEN demo.gdp_per_capita >= 40000 THEN '40k+'
		ELSE 'ERROR'
	END AS gdp_bucket	
FROM cases_deaths cd
JOIN demographics demo ON demo.location = cd.location AND demo.record_date = cd.record_date
WHERE cd.continent IS NOT NULL
AND demo.gdp_per_capita IS NOT NULL
GROUP BY 1, 2, 3)
SELECT
	gdp_bucket AS gdp,
    ROUND(AVG(total_cases_per_million), 2) AS cases_per_million,
    ROUND(AVG(total_deaths_per_million), 2) AS deaths_per_million,
    CASE
		WHEN gdp_bucket = '<10k' THEN COUNT(location)
        WHEN gdp_bucket = '10k - 20k' THEN COUNT(location)
        WHEN gdp_bucket = '20k - 30k' THEN COUNT(location)
        WHEN gdp_bucket = '30k - 40k' THEN COUNT(location)
        WHEN gdp_bucket = '40k+' THEN COUNT(location)
	END AS num_countries
FROM country_cases_gdp
GROUP BY 1
;

